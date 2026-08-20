# Accounts, API Keys & Organizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real user accounts (signup/login/logout), self-service API keys tied to a user, and organizations with membership, all with a minimal server-rendered web UI — without ever letting the content-serving host (`content.mcpublish.ai`) gain session/cookie capability.

**Architecture:** A new `WebController < ActionController::Base` base class (full session/cookie/CSRF/view-rendering support) sits alongside the existing `ApplicationController < ActionController::API` (used by `McpController`) and `ContentController < ActionController::API` (used for artifact serving) — neither of the latter two changes. Session/cookie middleware is added to the global Rack stack (the officially-documented pattern for API-only apps that need sessions for a subset of controllers — see the Rails Guides "Using Session Middlewares" section), but `ActionController::API` subclasses never include the `Cookies`/`Session` modules regardless of middleware presence, so isolation holds by construction, not by convention. This is this plan's single most important correctness property — Task 1 includes a regression test proving it.

**Tech Stack:** Same as the existing app (Rails 8 API-only mode, PostgreSQL, RSpec) plus `bcrypt` (already present, commented out, in the Gemfile) for `has_secure_password`. Plain server-rendered ERB views, no asset pipeline, no JS framework, no CSS — this UI is intentionally bare-bones.

## Global Constraints

- This plan is sub-project 2+3's foundation layer only: **accounts, API keys, and organizations**. It does not touch `Artifact`, `McpController`'s tool logic, or content serving at all — those changes (visibility, sharing, gated content-serving) are a separate, later plan that builds on top of what's delivered here.
- The session cookie must be **host-only** — do not pass a `domain:` option to the session store config. Omitting `domain:` is what makes the cookie scoped to exactly the responding host; setting `domain: "mcpublish.ai"` would be **wrong** despite looking like the "obviously correct" value — it adds a `Domain` attribute that makes browsers also send the cookie to `content.mcpublish.ai`.
- `ContentController` and `McpController` must keep inheriting from `ActionController::API` (directly, or via `ApplicationController < ActionController::API`) — never `ActionController::Base`, never `WebController`.
- Auth is hand-rolled (`has_secure_password` + a plain session controller) — no Devise or other auth gem.
- Organization roles are exactly `admin`/`member` — no finer-grained permissions.
- Password reset, artifact-browsing UI, and org-settings UI beyond create/list/invite/remove-member are explicitly out of scope (deferred to a later sub-project).
- `ApiKey.issue!`'s `user:` keyword argument is **optional**, defaulting to `nil` — this keeps every existing spec across the whole app (which calls `ApiKey.issue!(label: "...")` with no user) working unchanged. Self-service-issued keys always pass a real user; this is a deliberate, backward-compatible choice, not an oversight — do not make `user:` required or go update the existing spec files' calls.

---

## Task 1: Users Model, Session Middleware & WebController

**Files:**
- Modify: `Gemfile`
- Create: `db/migrate/<timestamp>_create_users.rb`
- Create: `app/models/user.rb`
- Modify: `config/application.rb`
- Create: `app/controllers/concerns/authenticatable.rb`
- Create: `app/controllers/web_controller.rb`
- Create: `app/views/layouts/web.html.erb`
- Test: `spec/models/user_spec.rb`
- Test: `spec/requests/session_isolation_spec.rb`

**Interfaces:**
- Produces: `User` (`email`, `password`/`password_confirmation` via `has_secure_password`, normalized-lowercase email, `authenticate(raw_password)` from `has_secure_password`); `WebController` (base class for all later human-facing controllers, includes `Authenticatable`); `Authenticatable#current_user`, `Authenticatable#require_login!` (private instance methods, `current_user` also exposed as a view helper).

- [ ] **Step 1: Write the failing User model spec**

Create `spec/models/user_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  it "creates a user with a valid email and password" do
    user = User.new(email: "Alice@Example.com", password: "password123", password_confirmation: "password123")
    expect(user).to be_valid
  end

  it "normalizes email to lowercase on save" do
    user = User.create!(email: "Alice@Example.com", password: "password123", password_confirmation: "password123")
    expect(user.email).to eq("alice@example.com")
  end

  it "requires a unique email, case-insensitively" do
    User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123")
    dupe = User.new(email: "ALICE@example.com", password: "password123", password_confirmation: "password123")

    expect(dupe).not_to be_valid
  end

  it "rejects a malformed email" do
    user = User.new(email: "not-an-email", password: "password123", password_confirmation: "password123")
    expect(user).not_to be_valid
  end

  it "requires a password of at least 8 characters" do
    user = User.new(email: "bob@example.com", password: "short", password_confirmation: "short")
    expect(user).not_to be_valid
  end

  it "authenticates with the correct password" do
    user = User.create!(email: "carol@example.com", password: "password123", password_confirmation: "password123")
    expect(user.authenticate("password123")).to eq(user)
    expect(user.authenticate("wrong")).to eq(false)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: FAIL — `uninitialized constant User`

- [ ] **Step 3: Enable bcrypt**

In `Gemfile`, uncomment the existing line (it's already present, just commented out):

```ruby
gem "bcrypt", "~> 3.1.7"
```

Run:

```bash
bundle install
```

- [ ] **Step 4: Generate and write the migration**

```bash
rails generate migration CreateUsers
```

Replace the generated file's contents with:

```ruby
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 5: Write the User model**

Create `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_secure_password

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 7: Add session/cookie middleware for the subset of controllers that need it**

In `config/application.rb`, inside the `class Application < Rails::Application` block, add (after the `config.api_only = true` line):

```ruby
    # config.api_only stays true — most of the app (McpController,
    # ContentController) needs no session at all. These two middlewares add
    # session/cookie support to the Rack stack for the controllers that
    # explicitly opt in (WebController subclasses, via ActionController::Base).
    # ActionController::API subclasses never include the Cookies/Session
    # modules regardless of middleware presence, so this cannot leak into
    # McpController or ContentController — see spec/requests/session_isolation_spec.rb.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_mcpublish_session"
```

- [ ] **Step 8: Write the Authenticatable concern**

Create `app/controllers/concerns/authenticatable.rb`:

```ruby
module Authenticatable
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  def require_login!
    redirect_to login_path, alert: "Please log in first" unless current_user
  end
end
```

- [ ] **Step 9: Write WebController and the shared layout**

Create `app/controllers/web_controller.rb`:

```ruby
class WebController < ActionController::Base
  protect_from_forgery with: :exception
  include Authenticatable

  # Rails' automatic layout lookup matches the controller name
  # (e.g. layouts/account, layouts/sessions) with a fallback to
  # layouts/application — neither exists, so without this the
  # layouts/web.html.erb template below would silently never render.
  layout "web"
end
```

Create `app/views/layouts/web.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>mcpublish</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
  </head>
  <body>
    <% flash.each do |type, message| %>
      <p role="alert"><%= message %></p>
    <% end %>
    <%= yield %>
  </body>
</html>
```

- [ ] **Step 10: Write the session-isolation regression spec**

This is the plan's most important test — it proves adding session middleware did not compromise the isolation `McpController`/`ContentController` depend on. Create `spec/requests/session_isolation_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Session middleware does not leak into API-only hosts", type: :request do
  it "does not set a cookie on POST /mcp" do
    token = ApiKey.issue!(label: "Alice").last

    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }

    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "does not set a cookie on GET content.mcpublish.ai/p/:slug" do
    api_key = ApiKey.issue!(label: "Alice").first
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 5)
    ArtifactStorage.client.stub_responses(:get_object, body: "<html>hi</html>")

    host! "content.mcpublish.ai"
    get "/p/#{artifact.slug}"

    expect(response.headers["Set-Cookie"]).to be_nil
  end
end
```

- [ ] **Step 11: Run the full suite to confirm no regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples (the two new specs plus every existing one, since nothing existing changed behavior)

- [ ] **Step 12: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate app/models/user.rb config/application.rb app/controllers/concerns/authenticatable.rb app/controllers/web_controller.rb app/views/layouts/web.html.erb spec/models/user_spec.rb spec/requests/session_isolation_spec.rb db/schema.rb
git commit -m "Add User model, session middleware, and WebController without breaking content/mcp isolation"
```

---

## Task 2: Signup, Login, Logout & Account Page

**Files:**
- Create: `app/controllers/users_controller.rb`
- Create: `app/controllers/sessions_controller.rb`
- Create: `app/controllers/account_controller.rb`
- Create: `app/views/users/new.html.erb`
- Create: `app/views/sessions/new.html.erb`
- Create: `app/views/account/show.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/signup_spec.rb`
- Test: `spec/requests/login_logout_spec.rb`

**Interfaces:**
- Consumes: `User` (Task 1), `WebController`/`Authenticatable#current_user`/`#require_login!` (Task 1).
- Produces: `signup_path` (GET/POST `/signup`), `login_path` (GET/POST `/login`), `logout_path` (DELETE `/logout`), `account_path` (GET `/account`, requires login). `account_path` is the stable post-login landing page — later tasks append links to `app/views/account/show.html.erb` as their features land, rather than this task hardcoding forward references to routes that don't exist yet.

- [ ] **Step 1: Write the failing signup request spec**

Create `spec/requests/signup_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Signup", type: :request do
  it "creates a user and signs them in" do
    post "/signup", params: { user: { email: "new@example.com", password: "password123", password_confirmation: "password123" } }

    expect(response).to redirect_to("/account")
    follow_redirect!
    expect(response.body).to include("new@example.com")
  end

  it "re-renders the form with errors on invalid input" do
    post "/signup", params: { user: { email: "not-an-email", password: "short", password_confirmation: "short" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(User.count).to eq(0)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: FAIL — no route matches `POST /signup`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, inside the existing `constraints(->(req) { !on_content_host.call(req) }) do ... end` block, add after `post "/mcp", to: "mcp#create"`:

```ruby
    get "/signup", to: "users#new", as: :signup
    post "/signup", to: "users#create"
    get "/login", to: "sessions#new", as: :login
    post "/login", to: "sessions#create"
    delete "/logout", to: "sessions#destroy", as: :logout
    get "/account", to: "account#show", as: :account
```

- [ ] **Step 4: Write UsersController**

Create `app/controllers/users_controller.rb`:

```ruby
class UsersController < WebController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      session[:user_id] = @user.id
      redirect_to account_path, notice: "Account created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
```

- [ ] **Step 5: Write the signup view**

Create `app/views/users/new.html.erb`:

```erb
<h1>Sign up</h1>

<% if @user.errors.any? %>
  <ul role="alert">
    <% @user.errors.full_messages.each do |message| %>
      <li><%= message %></li>
    <% end %>
  </ul>
<% end %>

<%= form_with model: @user, url: signup_path, local: true do |f| %>
  <div>
    <%= f.label :email %>
    <%= f.email_field :email %>
  </div>
  <div>
    <%= f.label :password %>
    <%= f.password_field :password %>
  </div>
  <div>
    <%= f.label :password_confirmation %>
    <%= f.password_field :password_confirmation %>
  </div>
  <%= f.submit "Sign up" %>
<% end %>
```

- [ ] **Step 6: Write AccountController and its view**

Create `app/controllers/account_controller.rb`:

```ruby
class AccountController < WebController
  before_action :require_login!

  def show
  end
end
```

Create `app/views/account/show.html.erb`:

```erb
<h1>Account</h1>
<p>Signed in as <%= current_user.email %></p>
<%= button_to "Log out", logout_path, method: :delete %>
```

- [ ] **Step 7: Run the signup spec to verify it passes**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 8: Write the failing login/logout request spec**

Create `spec/requests/login_logout_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Login and logout", type: :request do
  let!(:user) { User.create!(email: "dana@example.com", password: "password123", password_confirmation: "password123") }

  it "logs in with correct credentials and reaches the account page" do
    post "/login", params: { email: "dana@example.com", password: "password123" }

    expect(response).to redirect_to("/account")
    follow_redirect!
    expect(response.body).to include("dana@example.com")
  end

  it "rejects incorrect credentials" do
    post "/login", params: { email: "dana@example.com", password: "wrong" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires login to view the account page" do
    get "/account"
    expect(response).to redirect_to("/login")
  end

  it "logs out and revokes access to the account page" do
    post "/login", params: { email: "dana@example.com", password: "password123" }

    delete "/logout"
    expect(response).to redirect_to("/login")

    get "/account"
    expect(response).to redirect_to("/login")
  end
end
```

- [ ] **Step 9: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/login_logout_spec.rb`
Expected: FAIL — no route matches `POST /login`

- [ ] **Step 10: Write SessionsController**

Create `app/controllers/sessions_controller.rb`:

```ruby
class SessionsController < WebController
  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to account_path, notice: "Signed in"
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Signed out"
  end
end
```

- [ ] **Step 11: Write the login view**

Create `app/views/sessions/new.html.erb`:

```erb
<h1>Log in</h1>

<%= form_with url: login_path, local: true do |f| %>
  <div>
    <%= f.label :email %>
    <%= f.email_field :email %>
  </div>
  <div>
    <%= f.label :password %>
    <%= f.password_field :password %>
  </div>
  <%= f.submit "Log in" %>
<% end %>
```

- [ ] **Step 12: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/login_logout_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 13: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 14: Commit**

```bash
git add app/controllers/users_controller.rb app/controllers/sessions_controller.rb app/controllers/account_controller.rb app/views/users app/views/sessions app/views/account config/routes.rb spec/requests/signup_spec.rb spec/requests/login_logout_spec.rb
git commit -m "Add signup, login, logout, and the account landing page"
```

---

## Task 3: API Key Ownership

**Files:**
- Create: `db/migrate/<timestamp>_add_user_to_api_keys.rb`
- Modify: `app/models/api_key.rb`
- Modify: `app/models/user.rb`
- Delete: `lib/tasks/api_keys.rake`
- Test: `spec/models/api_key_spec.rb`

**Interfaces:**
- Consumes: `User` (Task 1).
- Produces: `ApiKey.issue!(label:, user: nil)` → `[ api_key, raw_token ]` (backward-compatible — `user:` is optional, see Global Constraints); `ApiKey#user`; `User#api_keys`.

- [ ] **Step 1: Write the failing spec addition**

Add to `spec/models/api_key_spec.rb` (inside the existing `describe ".issue!"` block, after the existing examples):

```ruby
    it "associates the key with a user when one is given" do
      user = User.create!(email: "eve@example.com", password: "password123", password_confirmation: "password123")
      api_key, = ApiKey.issue!(label: "Eve's key", user: user)

      expect(api_key.user).to eq(user)
      expect(user.api_keys).to include(api_key)
    end

    it "still works with no user (backward compatible with existing manual-issuance callers)" do
      api_key, = ApiKey.issue!(label: "Ownerless")
      expect(api_key.user).to be_nil
    end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/api_key_spec.rb`
Expected: FAIL — `ApiKey` has no `user` association yet

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration AddUserToApiKeys
```

Replace the generated file's contents with:

```ruby
class AddUserToApiKeys < ActiveRecord::Migration[8.0]
  def change
    add_reference :api_keys, :user, foreign_key: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Update the ApiKey model**

In `app/models/api_key.rb`, add `belongs_to :user, optional: true` as the first line inside the class (before `has_many :artifacts`), and update `.issue!` to accept and pass through the optional `user:` keyword:

```ruby
class ApiKey < ApplicationRecord
  belongs_to :user, optional: true
  has_many :artifacts, dependent: :destroy

  TOKEN_PREFIX = "mcpub_".freeze

  validates :label, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def self.issue!(label:, user: nil)
    raw_token = TOKEN_PREFIX + SecureRandom.hex(32)
    api_key = create!(label: label, user: user, token_digest: digest(raw_token))
    [ api_key, raw_token ]
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    api_key = find_by(token_digest: digest(raw_token))
    return nil if api_key.nil?
    return nil if api_key.revoked?

    api_key
  end

  def revoked?
    revoked_at.present?
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest
end
```

- [ ] **Step 5: Add the inverse association to User**

In `app/models/user.rb`, add `has_many :api_keys, dependent: :destroy` as the first line inside the class (before `has_secure_password`):

```ruby
  has_many :api_keys, dependent: :destroy
```

- [ ] **Step 6: Remove the manual issuance rake task**

Self-service (Task 4) replaces it entirely.

```bash
rm lib/tasks/api_keys.rake
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/api_key_spec.rb`
Expected: PASS (10 examples)

- [ ] **Step 8: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples (every existing `ApiKey.issue!(label: "...")` call across the whole suite keeps working — `user:` is optional)

- [ ] **Step 9: Commit**

```bash
git add db/migrate app/models/api_key.rb app/models/user.rb spec/models/api_key_spec.rb db/schema.rb
git rm lib/tasks/api_keys.rake
git commit -m "Give API keys an optional owning user; remove manual issuance rake task"
```

---

## Task 4: Self-Service API Key UI

**Files:**
- Create: `app/controllers/api_keys_controller.rb`
- Create: `app/views/api_keys/index.html.erb`
- Modify: `app/views/account/show.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api_keys_spec.rb`

**Interfaces:**
- Consumes: `ApiKey.issue!(label:, user:)` (Task 3), `Authenticatable#require_login!`/`#current_user` (Task 1).
- Produces: `api_keys_path` (GET `/api_keys`, POST `/api_keys`), `api_key_path(api_key)` (DELETE, revokes).

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api_keys_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "API key management", type: :request do
  let(:user) { User.create!(email: "frank@example.com", password: "password123", password_confirmation: "password123") }
  let(:other_user) { User.create!(email: "gina@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "requires login" do
    get "/api_keys"
    expect(response).to redirect_to("/login")
  end

  it "generates a new key for the signed-in user" do
    sign_in_as(user)

    expect {
      post "/api_keys", params: { label: "My laptop" }
    }.to change { user.api_keys.count }.by(1)

    expect(response).to redirect_to("/api_keys")
    expect(user.api_keys.last.label).to eq("My laptop")
  end

  it "revokes only the current user's own key" do
    sign_in_as(user)
    api_key, = ApiKey.issue!(label: "Mine", user: user)

    delete "/api_keys/#{api_key.id}"

    expect(api_key.reload.revoked?).to eq(true)
  end

  it "cannot revoke another user's key" do
    sign_in_as(user)
    other_key, = ApiKey.issue!(label: "Not yours", user: other_user)

    delete "/api_keys/#{other_key.id}"

    expect(response).to have_http_status(:not_found)
    expect(other_key.reload.revoked?).to eq(false)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/api_keys_spec.rb`
Expected: FAIL — no route matches `GET /api_keys`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, inside the existing `constraints(->(req) { !on_content_host.call(req) }) do ... end` block, add after the `/account` route:

```ruby
    resources :api_keys, only: [ :index, :create, :destroy ]
```

- [ ] **Step 4: Write ApiKeysController**

Create `app/controllers/api_keys_controller.rb`:

```ruby
class ApiKeysController < WebController
  before_action :require_login!

  def index
    @api_keys = current_user.api_keys.order(created_at: :desc)
  end

  def create
    _api_key, raw_token = ApiKey.issue!(label: params[:label], user: current_user)
    redirect_to api_keys_path, notice: "New API key (copy it now, it will not be shown again): #{raw_token}"
  end

  def destroy
    api_key = current_user.api_keys.find(params[:id])
    api_key.update!(revoked_at: Time.current)
    redirect_to api_keys_path, notice: "API key revoked"
  end
end
```

- [ ] **Step 5: Write the API keys view**

Create `app/views/api_keys/index.html.erb`:

```erb
<h1>API keys</h1>

<ul>
  <% @api_keys.each do |api_key| %>
    <li>
      <%= api_key.label %>
      <% if api_key.revoked? %>
        (revoked)
      <% else %>
        <%= button_to "Revoke", api_key_path(api_key), method: :delete %>
      <% end %>
    </li>
  <% end %>
</ul>

<%= form_with url: api_keys_path, local: true do |f| %>
  <%= f.label :label, "New key label" %>
  <%= f.text_field :label %>
  <%= f.submit "Generate key" %>
<% end %>
```

- [ ] **Step 6: Link to the API keys page from the account page**

In `app/views/account/show.html.erb`, add before the logout button:

```erb
<p><%= link_to "API keys", api_keys_path %></p>
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/api_keys_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 8: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 9: Commit**

```bash
git add app/controllers/api_keys_controller.rb app/views/api_keys app/views/account/show.html.erb config/routes.rb spec/requests/api_keys_spec.rb
git commit -m "Add self-service API key generation and revocation"
```

---

## Task 5: Organizations & Memberships

**Files:**
- Create: `db/migrate/<timestamp>_create_organizations.rb`
- Create: `db/migrate/<timestamp>_create_organization_memberships.rb`
- Create: `app/models/organization.rb`
- Create: `app/models/organization_membership.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/organization_spec.rb`
- Test: `spec/models/organization_membership_spec.rb`

**Interfaces:**
- Consumes: `User` (Task 1).
- Produces: `Organization` (`name`, `slug`); `OrganizationMembership` (`user`, `organization`, `role` — `"admin"`/`"member"`, `#admin?`); `Organization#users`, `Organization#organization_memberships`; `User#organizations`, `User#organization_memberships`. Later tasks use `current_user.organizations` and `OrganizationMembership::ROLES`.

- [ ] **Step 1: Write the failing Organization spec**

Create `spec/models/organization_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Organization, type: :model do
  it "requires a name" do
    org = Organization.new(slug: "acme")
    expect(org).not_to be_valid
  end

  it "requires a unique slug" do
    Organization.create!(name: "Acme", slug: "acme")
    dupe = Organization.new(name: "Acme Two", slug: "acme")

    expect(dupe).not_to be_valid
  end

  it "rejects a slug with invalid characters" do
    org = Organization.new(name: "Acme", slug: "Not Valid!")
    expect(org).not_to be_valid
  end

  it "accepts a lowercase, hyphenated slug" do
    org = Organization.new(name: "Acme", slug: "acme-co")
    expect(org).to be_valid
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/organization_spec.rb`
Expected: FAIL — `uninitialized constant Organization`

- [ ] **Step 3: Generate and write the organizations migration**

```bash
rails generate migration CreateOrganizations
```

Replace the generated file's contents with:

```ruby
class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :organizations, :slug, unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Write the Organization model**

Create `app/models/organization.rb`:

```ruby
class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+\z/, message: "may only contain lowercase letters, numbers, and hyphens" }
end
```

- [ ] **Step 5: Run the Organization spec to verify it passes**

Run: `bundle exec rspec spec/models/organization_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 6: Write the failing OrganizationMembership spec**

Create `spec/models/organization_membership_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe OrganizationMembership, type: :model do
  let(:user) { User.create!(email: "hank@example.com", password: "password123", password_confirmation: "password123") }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  it "accepts admin and member roles" do
    membership = OrganizationMembership.new(user: user, organization: organization, role: "admin")
    expect(membership).to be_valid
  end

  it "rejects an invalid role" do
    membership = OrganizationMembership.new(user: user, organization: organization, role: "owner")
    expect(membership).not_to be_valid
  end

  it "prevents the same user joining the same org twice" do
    OrganizationMembership.create!(user: user, organization: organization, role: "member")
    dupe = OrganizationMembership.new(user: user, organization: organization, role: "member")

    expect(dupe).not_to be_valid
  end

  it "reports admin? correctly" do
    admin = OrganizationMembership.new(role: "admin")
    member = OrganizationMembership.new(role: "member")

    expect(admin.admin?).to eq(true)
    expect(member.admin?).to eq(false)
  end

  it "is reachable via user#organizations and organization#users" do
    OrganizationMembership.create!(user: user, organization: organization, role: "admin")

    expect(user.organizations).to include(organization)
    expect(organization.users).to include(user)
  end
end
```

- [ ] **Step 7: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/organization_membership_spec.rb`
Expected: FAIL — `uninitialized constant OrganizationMembership`

- [ ] **Step 8: Generate and write the memberships migration**

```bash
rails generate migration CreateOrganizationMemberships
```

Replace the generated file's contents with:

```ruby
class CreateOrganizationMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :organization_memberships, [ :user_id, :organization_id ], unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 9: Write the OrganizationMembership model**

Create `app/models/organization_membership.rb`:

```ruby
class OrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  ROLES = %w[admin member].freeze

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }

  def admin?
    role == "admin"
  end
end
```

- [ ] **Step 10: Add the inverse associations to User**

In `app/models/user.rb`, add these two lines alongside the existing `has_many :api_keys, dependent: :destroy`:

```ruby
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
```

- [ ] **Step 11: Run the OrganizationMembership spec to verify it passes**

Run: `bundle exec rspec spec/models/organization_membership_spec.rb`
Expected: PASS (5 examples)

- [ ] **Step 12: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 13: Commit**

```bash
git add db/migrate app/models/organization.rb app/models/organization_membership.rb app/models/user.rb spec/models/organization_spec.rb spec/models/organization_membership_spec.rb db/schema.rb
git commit -m "Add Organization and OrganizationMembership models"
```

---

## Task 6: Organization Invites & Signup-Time Claiming

**Files:**
- Create: `db/migrate/<timestamp>_create_organization_invites.rb`
- Create: `app/models/organization_invite.rb`
- Modify: `app/models/organization.rb`
- Modify: `app/controllers/users_controller.rb`
- Test: `spec/models/organization_invite_spec.rb`
- Test: `spec/requests/signup_spec.rb`

**Interfaces:**
- Consumes: `Organization`, `OrganizationMembership` (Task 5), `UsersController#create` (Task 2).
- Produces: `OrganizationInvite` (`organization`, `email`). Claimed automatically at signup — later tasks (org invite UI) create these rows; this task only defines the model and the claiming side.

- [ ] **Step 1: Write the failing OrganizationInvite spec**

Create `spec/models/organization_invite_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe OrganizationInvite, type: :model do
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  it "requires a valid email" do
    invite = OrganizationInvite.new(organization: organization, email: "not-an-email")
    expect(invite).not_to be_valid
  end

  it "is valid with an organization and email" do
    invite = OrganizationInvite.new(organization: organization, email: "invitee@example.com")
    expect(invite).to be_valid
  end

  it "is destroyed when its organization is destroyed" do
    invite = OrganizationInvite.create!(organization: organization, email: "invitee@example.com")
    organization.destroy!

    expect(OrganizationInvite.exists?(invite.id)).to eq(false)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/organization_invite_spec.rb`
Expected: FAIL — `uninitialized constant OrganizationInvite`

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration CreateOrganizationInvites
```

Replace the generated file's contents with:

```ruby
class CreateOrganizationInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_invites do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false

      t.timestamps
    end

    add_index :organization_invites, [ :organization_id, :email ], unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Write the OrganizationInvite model**

Create `app/models/organization_invite.rb`:

```ruby
class OrganizationInvite < ApplicationRecord
  belongs_to :organization

  before_validation :normalize_email

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
```

- [ ] **Step 5: Add the inverse association to Organization**

In `app/models/organization.rb`, add alongside the existing `has_many :organization_memberships, dependent: :destroy`:

```ruby
  has_many :organization_invites, dependent: :destroy
```

- [ ] **Step 6: Run the OrganizationInvite spec to verify it passes**

Run: `bundle exec rspec spec/models/organization_invite_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 7: Write the failing signup-claims-invites spec**

Add to `spec/requests/signup_spec.rb`, as a new example inside the existing `RSpec.describe "Signup"` block:

```ruby
  it "claims any pending organization invites matching the new user's email" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationInvite.create!(organization: organization, email: "invited@example.com")

    post "/signup", params: { user: { email: "invited@example.com", password: "password123", password_confirmation: "password123" } }

    user = User.find_by!(email: "invited@example.com")
    expect(user.organizations).to include(organization)
    expect(OrganizationInvite.exists?(organization: organization, email: "invited@example.com")).to eq(false)
  end
```

- [ ] **Step 8: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: FAIL — the user is created but not added to the organization

- [ ] **Step 9: Wire invite-claiming into UsersController#create**

In `app/controllers/users_controller.rb`, replace the `create` method:

```ruby
  def create
    @user = User.new(user_params)

    if @user.save
      claim_pending_invites(@user)
      session[:user_id] = @user.id
      redirect_to account_path, notice: "Account created"
    else
      render :new, status: :unprocessable_entity
    end
  end
```

Add a private method below `user_params`:

```ruby
  def claim_pending_invites(user)
    OrganizationInvite.where(email: user.email).find_each do |invite|
      OrganizationMembership.create!(user: user, organization: invite.organization, role: "member")
      invite.destroy!
    end
  end
```

- [ ] **Step 10: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 11: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 12: Commit**

```bash
git add db/migrate app/models/organization_invite.rb app/models/organization.rb app/controllers/users_controller.rb spec/models/organization_invite_spec.rb spec/requests/signup_spec.rb db/schema.rb
git commit -m "Add OrganizationInvite model with automatic claiming at signup"
```

---

## Task 7: Organizations UI

**Files:**
- Create: `app/controllers/organizations_controller.rb`
- Create: `app/views/organizations/index.html.erb`
- Create: `app/views/organizations/new.html.erb`
- Create: `app/views/organizations/show.html.erb`
- Modify: `app/views/account/show.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/organizations_spec.rb`

**Interfaces:**
- Consumes: `Organization`, `OrganizationMembership`, `OrganizationInvite` (Tasks 5–6), `Authenticatable#require_login!`/`#current_user` (Task 1).
- Produces: `organizations_path` (GET/POST), `new_organization_path` (GET), `organization_path(org)` (GET), `invite_organization_path(org)` (POST), `remove_member_organization_path(org, membership_id:)` (DELETE).

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/organizations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:admin) { User.create!(email: "ivy@example.com", password: "password123", password_confirmation: "password123") }
  let(:member) { User.create!(email: "jack@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "requires login" do
    get "/organizations"
    expect(response).to redirect_to("/login")
  end

  it "creates an organization and makes the creator an admin" do
    sign_in_as(admin)

    post "/organizations", params: { organization: { name: "Acme", slug: "acme" } }

    organization = Organization.find_by!(slug: "acme")
    membership = organization.organization_memberships.find_by!(user: admin)
    expect(membership.admin?).to eq(true)
  end

  it "adds an existing user directly as a member when invited" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    member # eager-create

    post "/organizations/#{organization.id}/invite", params: { email: member.email }

    expect(organization.users).to include(member)
    expect(OrganizationInvite.exists?(organization: organization, email: member.email)).to eq(false)
  end

  it "creates a pending invite for an email with no account yet" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")

    post "/organizations/#{organization.id}/invite", params: { email: "notyet@example.com" }

    expect(OrganizationInvite.exists?(organization: organization, email: "notyet@example.com")).to eq(true)
  end

  it "lets an admin remove a member" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    membership = OrganizationMembership.create!(user: member, organization: organization, role: "member")

    delete "/organizations/#{organization.id}/members/#{membership.id}"

    expect(OrganizationMembership.exists?(membership.id)).to eq(false)
  end

  it "does not let a non-admin member remove anyone" do
    sign_in_as(member)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    membership = OrganizationMembership.create!(user: member, organization: organization, role: "member")

    delete "/organizations/#{organization.id}/members/#{membership.id}"

    expect(response).to have_http_status(:not_found)
    expect(OrganizationMembership.exists?(membership.id)).to eq(true)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/organizations_spec.rb`
Expected: FAIL — no route matches `GET /organizations`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, inside the existing `constraints(->(req) { !on_content_host.call(req) }) do ... end` block, add after the `resources :api_keys` line:

```ruby
    resources :organizations, only: [ :index, :new, :create, :show ] do
      member do
        post :invite
        delete "members/:membership_id", to: "organizations#remove_member", as: :remove_member
      end
    end
```

- [ ] **Step 4: Write OrganizationsController**

Create `app/controllers/organizations_controller.rb`:

```ruby
class OrganizationsController < WebController
  before_action :require_login!

  def index
    @organizations = current_user.organizations
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(organization_params)

    ActiveRecord::Base.transaction do
      @organization.save!
      OrganizationMembership.create!(user: current_user, organization: @organization, role: "admin")
    end

    redirect_to organizations_path, notice: "Organization created"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @organization = current_user.organizations.find(params[:id])
    @memberships = @organization.organization_memberships.includes(:user)
  end

  def invite
    organization = admin_organization(params[:id])
    email = params[:email].to_s.strip.downcase
    existing_user = User.find_by(email: email)

    if existing_user && organization.users.include?(existing_user)
      redirect_to organization_path(organization), alert: "Already a member"
    elsif existing_user
      OrganizationMembership.create!(user: existing_user, organization: organization, role: "member")
      redirect_to organization_path(organization), notice: "#{email} added"
    else
      OrganizationInvite.find_or_create_by!(organization: organization, email: email)
      redirect_to organization_path(organization), notice: "Invite sent to #{email}"
    end
  end

  def remove_member
    organization = admin_organization(params[:id])
    membership = organization.organization_memberships.find(params[:membership_id])
    membership.destroy!
    redirect_to organization_path(organization), notice: "Member removed"
  end

  private

  def admin_organization(id)
    organization = current_user.organizations.find(id)
    membership = organization.organization_memberships.find_by(user: current_user)
    raise ActiveRecord::RecordNotFound unless membership&.admin?

    organization
  end

  def organization_params
    params.require(:organization).permit(:name, :slug)
  end
end
```

- [ ] **Step 5: Write the organizations views**

Create `app/views/organizations/index.html.erb`:

```erb
<h1>Your organizations</h1>

<ul>
  <% @organizations.each do |org| %>
    <li><%= link_to org.name, organization_path(org) %></li>
  <% end %>
</ul>

<%= link_to "New organization", new_organization_path %>
```

Create `app/views/organizations/new.html.erb`:

```erb
<h1>New organization</h1>

<% if @organization.errors.any? %>
  <ul role="alert">
    <% @organization.errors.full_messages.each do |message| %>
      <li><%= message %></li>
    <% end %>
  </ul>
<% end %>

<%= form_with model: @organization, url: organizations_path, local: true do |f| %>
  <div>
    <%= f.label :name %>
    <%= f.text_field :name %>
  </div>
  <div>
    <%= f.label :slug %>
    <%= f.text_field :slug %>
  </div>
  <%= f.submit "Create" %>
<% end %>
```

Create `app/views/organizations/show.html.erb`:

```erb
<h1><%= @organization.name %></h1>

<ul>
  <% @memberships.each do |membership| %>
    <li>
      <%= membership.user.email %> (<%= membership.role %>)
      <%= button_to "Remove", remove_member_organization_path(@organization, membership_id: membership.id), method: :delete %>
    </li>
  <% end %>
</ul>

<%= form_with url: invite_organization_path(@organization), method: :post, local: true do |f| %>
  <%= f.label :email, "Invite by email" %>
  <%= f.email_field :email %>
  <%= f.submit "Invite" %>
<% end %>
```

- [ ] **Step 6: Link to organizations from the account page**

In `app/views/account/show.html.erb`, add alongside the existing "API keys" link:

```erb
<p><%= link_to "Organizations", organizations_path %></p>
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/organizations_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 8: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 9: Commit**

```bash
git add app/controllers/organizations_controller.rb app/views/organizations app/views/account/show.html.erb config/routes.rb spec/requests/organizations_spec.rb
git commit -m "Add organization creation, invites, and membership management UI"
```
