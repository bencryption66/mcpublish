# Artifact Visibility & Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every artifact a visibility (`private`/`organisation`/`shared`/`public`), let agents set and change it via the MCP tools, and let a signed-in human view a gated artifact they have permission to see — all without ever giving `content.mcpublish.ai` a session cookie.

**Architecture:** Ownership moves from `Artifact belongs_to :api_key` to `Artifact belongs_to :user` (a key authenticates a request; a user owns the artifact). `content.mcpublish.ai` still never touches sessions — for anything that isn't `public`, it redirects to a main-app endpoint (`ArtifactsController#view`) that has a real session, makes the permission decision, and hands back a short-lived signed token (`ActiveSupport::MessageVerifier`) in the redirect back to the content host. The content controller only ever verifies a token's signature/expiry/slug-match; it never makes a permission decision itself.

**Tech Stack:** Same as the shipped app (Rails 8, PostgreSQL, RSpec). No new gems — `ActiveSupport::MessageVerifier` is built into Rails.

## Global Constraints

- Ownership: `Artifact belongs_to :user` (not `:api_key`). The `api_key_id` column and `ApiKey#artifacts`/`Artifact#api_key` associations are removed entirely — a key that authenticates a request has no bearing on who owns the artifacts it acts on.
- An MCP `tools/call` request from an API key with **no owning user** is rejected with a clean tool error — it cannot own or act on artifacts. `initialize`/`tools/list` are unaffected (they don't touch artifacts).
- Visibility values are exactly `private` (default), `organisation`, `shared`, `public` — no others.
- `update_artifact`'s `visibility`/`organization`/`shared_with` params are independent of `html` — a visibility-only update must not require resending content. Each provided param **replaces** the current value; omitted params are left unchanged. Switching away from `organisation` clears the artifact's `organization`; switching away from `shared` clears its `ArtifactShare` rows.
- `content.mcpublish.ai` (`ContentController`) must never gain session access — this plan does not touch its `session` guard (added in the accounts/orgs plan) and does not add any session/cookie logic there. Gated artifacts are served via a signed, short-lived (~1 hour), single-slug-scoped token in the URL, never a cookie.
- Not-found and not-permitted must be **identical** responses at `ArtifactsController#view` — a nonexistent slug and a real-but-forbidden one cannot be distinguished by a prober.
- No new gems. No changes to `Artifact`'s `slug`/`storage_key`/`byte_size` handling, `SlugGenerator`, `ArtifactStorage`, or anything in `content_controller.rb`'s S3-serving logic (`serve`) — only what's needed for the gating decision.

---

## Task 1: Migrate Artifact Ownership from ApiKey to User

**Files:**
- Create: `db/migrate/<timestamp>_migrate_artifact_ownership_to_user.rb`
- Modify: `app/models/artifact.rb`
- Modify: `app/models/api_key.rb`
- Modify: `app/models/user.rb`
- Modify: `app/services/mcp/tool_dispatcher.rb`
- Modify: `app/services/mcp/tools/publish_artifact.rb`
- Modify: `app/services/mcp/tools/update_artifact.rb`
- Modify: `app/services/mcp/tools/list_artifacts.rb`
- Modify: `app/services/mcp/tools/delete_artifact.rb`
- Modify: `app/controllers/mcp_controller.rb`
- Modify: `spec/models/artifact_spec.rb`
- Modify: `spec/requests/mcp_tools_call_spec.rb`
- Modify: `spec/requests/content_spec.rb`
- Modify: `spec/requests/content_host_routing_spec.rb`
- Modify: `spec/requests/session_isolation_spec.rb`

**Interfaces:**
- Consumes: `User` (existing, from the accounts/orgs plan).
- Produces: `Artifact belongs_to :user`; `User#artifacts`; `Mcp::ToolDispatcher.call(tool_name:, arguments:, user:)` (was `api_key:`); every `Mcp::Tools::*` class now takes `.new(user:, arguments:)` (was `api_key:`). Later tasks in this plan build on `user.artifacts` as the ownership-scoping pattern throughout.

- [ ] **Step 1: Write the failing model spec**

Replace the full contents of `spec/models/artifact_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Artifact, type: :model do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }

  it "auto-assigns a slug on create" do
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to match(/\A[a-zA-Z0-9]{8}\z/)
  end

  it "does not overwrite an explicitly-set slug" do
    artifact = Artifact.create!(user: user, slug: "custom01", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to eq("custom01")
  end

  it "builds a content URL from the slug" do
    artifact = Artifact.create!(user: user, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://content.mcpublish.ai/p/abcd1234")
  end

  it "builds the content URL from the configured content host, not a hardcoded constant" do
    original_content_host = Rails.application.config.x.content_host
    Rails.application.config.x.content_host = "artifacts.example.com"

    artifact = Artifact.create!(user: user, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://artifacts.example.com/p/abcd1234")
  ensure
    Rails.application.config.x.content_host = original_content_host
  end

  it "requires a positive byte_size" do
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 0)
    expect(artifact).not_to be_valid
  end

  it "is accessible via user#artifacts" do
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10)
    expect(user.artifacts).to include(artifact)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/artifact_spec.rb`
Expected: FAIL — `Artifact` doesn't accept a `user:` attribute yet

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration MigrateArtifactOwnershipToUser
```

Replace the generated file's contents with:

```ruby
class MigrateArtifactOwnershipToUser < ActiveRecord::Migration[8.0]
  def change
    add_reference :artifacts, :user, foreign_key: true
    remove_reference :artifacts, :api_key, foreign_key: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Update the Artifact model**

Replace the full contents of `app/models/artifact.rb`:

```ruby
class Artifact < ApplicationRecord
  belongs_to :user

  validates :slug, presence: true, uniqueness: true
  validates :storage_key, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }

  before_validation :assign_slug, on: :create

  def url
    "https://#{Rails.application.config.x.content_host}/p/#{slug}"
  end

  private

  def assign_slug
    self.slug ||= SlugGenerator.generate_unique
  end
end
```

- [ ] **Step 5: Update ApiKey and User models**

In `app/models/api_key.rb`, remove the `has_many :artifacts, dependent: :destroy` line — the file should read:

```ruby
class ApiKey < ApplicationRecord
  belongs_to :user, optional: true

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

In `app/models/user.rb`, add `has_many :artifacts, dependent: :destroy` alongside the existing `has_many` lines — the file should read:

```ruby
class User < ApplicationRecord
  has_many :api_keys, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
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

- [ ] **Step 6: Run the model spec to verify it passes**

Run: `bundle exec rspec spec/models/artifact_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 7: Write the failing MCP tools/call spec**

Replace the full contents of `spec/requests/mcp_tools_call_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "MCP tools/call", type: :request do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let!(:api_key_pair) { ApiKey.issue!(label: "Alice", user: user) }
  let(:token) { api_key_pair.last }

  let(:other_user) { User.create!(email: "bob@example.com", password: "password123", password_confirmation: "password123") }
  let!(:other_key_pair) { ApiKey.issue!(label: "Bob", user: other_user) }
  let(:other_api_key) { other_key_pair.first }

  def call_tool(name, arguments, token: self.token, id: 1)
    post "/mcp",
      params: { jsonrpc: "2.0", id: id, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  describe "publish_artifact" do
    it "creates an artifact and returns its url" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>" })

      expect(result["result"]["url"]).to match(%r{\Ahttps://content\.mcpublish\.ai/p/[a-zA-Z0-9]{8}\z})
      expect(Artifact.count).to eq(1)
      expect(Artifact.first.user).to eq(user)
    end

    it "rejects a missing html argument" do
      result = call_tool("publish_artifact", {})

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "rejects html over the 5MB size limit" do
      oversized = "a" * (5.megabytes + 1)
      result = call_tool("publish_artifact", { html: oversized })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "surfaces an S3 failure as a retryable error and rolls back the record" do
      allow(ArtifactStorage).to receive(:put).and_raise(Aws::S3::Errors::ServiceError.new(nil, "boom"))

      result = call_tool("publish_artifact", { html: "<html>hi</html>" })

      expect(result["result"]["isError"]).to eq(true)
      expect(result["result"]["content"].first["text"]).to match(/retry/i)
      expect(Artifact.count).to eq(0)
    end

    it "surfaces a network failure (e.g. an S3 timeout) as a retryable error and rolls back the record" do
      allow(ArtifactStorage).to receive(:put)
        .and_raise(Seahorse::Client::NetworkingError.new(StandardError.new("timeout"), "boom"))

      result = call_tool("publish_artifact", { html: "<html>hi</html>" })

      expect(result["result"]["isError"]).to eq(true)
      expect(result["result"]["content"].first["text"]).to match(/retry/i)
      expect(Artifact.count).to eq(0)
    end

    it "rejects a request from an API key with no owning user" do
      ownerless_token = ApiKey.issue!(label: "Ownerless").last

      result = call_tool("publish_artifact", { html: "<html>hi</html>" }, token: ownerless_token)

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "retries with a fresh slug when a concurrent publish collides on the DB unique index" do
      original_save = Artifact.instance_method(:save!)
      attempt = 0
      allow_any_instance_of(Artifact).to receive(:save!) do |instance|
        attempt += 1
        raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint" if attempt == 1

        original_save.bind(instance).call
      end

      result = call_tool("publish_artifact", { html: "<html>race</html>" })

      expect(result["result"]["url"]).to match(%r{\Ahttps://content\.mcpublish\.ai/p/[a-zA-Z0-9]{8}\z})
      expect(Artifact.count).to eq(1)
      expect(attempt).to eq(2)
    end
  end

  describe "update_artifact" do
    it "overwrites the content of an owned artifact" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>" })
      slug = publish_result["result"]["slug"]

      result = call_tool("update_artifact", { slug: slug, html: "<html>v2</html>" })

      expect(result["result"]["slug"]).to eq(slug)
      expect(Artifact.find_by(slug: slug).byte_size).to eq("<html>v2</html>".bytesize)
    end

    it "returns a generic error for a nonexistent slug" do
      result = call_tool("update_artifact", { slug: "nosuchslug", html: "<html></html>" })
      expect(result["result"]["isError"]).to eq(true)
    end

    it "returns the identical generic error for a slug owned by someone else" do
      other_artifact = Artifact.create!(user: other_user, storage_key: "artifacts/x", byte_size: 5)

      not_found = call_tool("update_artifact", { slug: "nosuchslug", html: "<html></html>" })
      not_owned = call_tool("update_artifact", { slug: other_artifact.slug, html: "<html></html>" })

      expect(not_owned["result"]["content"]).to eq(not_found["result"]["content"])
    end
  end

  describe "list_artifacts" do
    it "returns only artifacts owned by the calling user" do
      call_tool("publish_artifact", { html: "<html>mine</html>" })
      Artifact.create!(user: other_user, storage_key: "artifacts/x", byte_size: 5)

      result = call_tool("list_artifacts", {})

      expect(result["result"]["artifacts"].length).to eq(1)
    end
  end

  describe "delete_artifact" do
    it "deletes an owned artifact" do
      publish_result = call_tool("publish_artifact", { html: "<html>bye</html>" })
      slug = publish_result["result"]["slug"]

      result = call_tool("delete_artifact", { slug: slug })

      expect(result["result"]["success"]).to eq(true)
      expect(Artifact.find_by(slug: slug)).to be_nil
    end

    it "returns the identical generic error for not-found and not-owned slugs" do
      other_artifact = Artifact.create!(user: other_user, storage_key: "artifacts/x", byte_size: 5)

      not_found = call_tool("delete_artifact", { slug: "nosuchslug" })
      not_owned = call_tool("delete_artifact", { slug: other_artifact.slug })

      expect(not_owned["result"]["content"]).to eq(not_found["result"]["content"])
      expect(Artifact.exists?(other_artifact.id)).to eq(true)
    end

    it "surfaces an S3 failure as a retryable error and does not destroy the record" do
      publish_result = call_tool("publish_artifact", { html: "<html>bye</html>" })
      slug = publish_result["result"]["slug"]

      allow(ArtifactStorage).to receive(:delete).and_raise(Aws::S3::Errors::ServiceError.new(nil, "boom"))

      result = call_tool("delete_artifact", { slug: slug })

      expect(result["result"]["isError"]).to eq(true)
      expect(result["result"]["content"].first["text"]).to match(/retry/i)
      expect(Artifact.find_by(slug: slug)).not_to be_nil
    end
  end

  describe "unexpected errors" do
    it "returns a generic isError result instead of a raw 500" do
      allow(Mcp::ToolDispatcher).to receive(:call).and_raise(RuntimeError, "boom")

      post "/mcp",
        params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "publish_artifact", arguments: { html: "<html>x</html>" } } }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["result"]["isError"]).to eq(true)
      expect(result["result"]["content"].first["text"]).to eq("Internal error, please retry")
    end
  end
end
```

- [ ] **Step 8: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: FAIL — tool classes still expect `api_key:`, and there's no "no owning user" rejection yet

- [ ] **Step 9: Update ToolDispatcher and the four tool classes**

Replace the full contents of `app/services/mcp/tool_dispatcher.rb`:

```ruby
module Mcp
  class ToolDispatcher
    class ToolError < StandardError; end

    def self.call(tool_name:, arguments:, user:)
      tool_class = tool_classes[tool_name]
      raise ToolError, "Unknown tool: #{tool_name}" unless tool_class

      tool_class.new(user: user, arguments: arguments).call
    end

    def self.tool_classes
      {
        "publish_artifact" => Mcp::Tools::PublishArtifact,
        "update_artifact" => Mcp::Tools::UpdateArtifact,
        "list_artifacts" => Mcp::Tools::ListArtifacts,
        "delete_artifact" => Mcp::Tools::DeleteArtifact
      }
    end
  end
end
```

Replace the full contents of `app/services/mcp/tools/publish_artifact.rb`:

```ruby
module Mcp
  module Tools
    class PublishArtifact
      MAX_BYTES = 5.megabytes
      MAX_SLUG_ATTEMPTS = 3

      def initialize(user:, arguments:)
        @user = user
        @html = arguments["html"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end

        artifact = create_artifact_with_retry

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end

      private

      # SlugGenerator checks Artifact.exists? before the caller inserts, so two
      # concurrent publishes can both pass that check for the same slug before
      # either commits — the DB's unique index then rejects the loser. Retry
      # with a freshly-generated slug rather than surfacing a raw DB error.
      def create_artifact_with_retry
        attempts = 0
        begin
          attempts += 1
          artifact = Artifact.new(
            user: @user,
            storage_key: "artifacts/#{SecureRandom.uuid}",
            byte_size: @html.bytesize
          )
          artifact.save!
          artifact
        rescue ActiveRecord::RecordNotUnique
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.errors.of_kind?(:slug, :taken)
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        end
      end
    end
  end
end
```

Replace the full contents of `app/services/mcp/tools/update_artifact.rb`:

```ruby
module Mcp
  module Tools
    class UpdateArtifact
      MAX_BYTES = Mcp::Tools::PublishArtifact::MAX_BYTES
      NOT_FOUND_MESSAGE = "Artifact not found".freeze

      def initialize(user:, arguments:)
        @user = user
        @slug = arguments["slug"]
        @html = arguments["html"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: slug" if @slug.blank?
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end

        artifact = @user.artifacts.find_by(slug: @slug)
        raise ToolDispatcher::ToolError, NOT_FOUND_MESSAGE unless artifact

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        artifact.update!(byte_size: @html.bytesize)

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end
    end
  end
end
```

Replace the full contents of `app/services/mcp/tools/list_artifacts.rb`:

```ruby
module Mcp
  module Tools
    class ListArtifacts
      def initialize(user:, arguments:)
        @user = user
      end

      def call
        artifacts = @user.artifacts.order(created_at: :desc).map do |artifact|
          {
            slug: artifact.slug,
            url: artifact.url,
            byte_size: artifact.byte_size,
            created_at: artifact.created_at.iso8601,
            updated_at: artifact.updated_at.iso8601
          }
        end

        { content: [ { type: "text", text: "#{artifacts.size} artifact(s)" } ], artifacts: artifacts }
      end
    end
  end
end
```

Replace the full contents of `app/services/mcp/tools/delete_artifact.rb`:

```ruby
module Mcp
  module Tools
    class DeleteArtifact
      NOT_FOUND_MESSAGE = Mcp::Tools::UpdateArtifact::NOT_FOUND_MESSAGE

      def initialize(user:, arguments:)
        @user = user
        @slug = arguments["slug"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: slug" if @slug.blank?

        artifact = @user.artifacts.find_by(slug: @slug)
        raise ToolDispatcher::ToolError, NOT_FOUND_MESSAGE unless artifact

        begin
          ArtifactStorage.delete(storage_key: artifact.storage_key)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        artifact.destroy!

        { content: [ { type: "text", text: "Deleted #{@slug}" } ], success: true }
      end
    end
  end
end
```

- [ ] **Step 10: Wire the "no owning user" rejection and update McpController**

In `app/controllers/mcp_controller.rb`, replace the `handle_tools_call` method:

```ruby
  def handle_tools_call
    tool_name = payload.dig("params", "name")
    arguments = payload.dig("params", "arguments") || {}
    user = current_api_key.user

    raise Mcp::ToolDispatcher::ToolError, "This API key has no owning user" unless user

    result = Mcp::ToolDispatcher.call(tool_name: tool_name, arguments: arguments, user: user)
    render json: success_response(result)
  rescue Mcp::ToolDispatcher::ToolError => e
    render json: success_response({ content: [ { type: "text", text: e.message } ], isError: true })
  rescue StandardError => e
    Rails.logger.error("Unexpected error in tools/call: #{e.class}: #{e.message}")
    render json: success_response({ content: [ { type: "text", text: "Internal error, please retry" } ], isError: true })
  end
```

- [ ] **Step 11: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: PASS (14 examples)

- [ ] **Step 12: Update the remaining specs that reference the old ownership model**

In `spec/requests/content_spec.rb`, change the top two `let` lines:

```ruby
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 20) }
```

In `spec/requests/content_host_routing_spec.rb`, in both examples, replace:

```ruby
      api_key = ApiKey.issue!(label: "Bob").first
      artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 20)
```

with:

```ruby
      user = User.create!(email: "bob@example.com", password: "password123", password_confirmation: "password123")
      artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 20)
```

(the second example uses `api_key = ApiKey.issue!(label: "Bob").first` / `Artifact.create!(api_key: api_key, ...)` without the extra indentation — apply the same replacement there, matching that example's indentation level).

In `spec/requests/session_isolation_spec.rb`, in the "does not set a cookie on GET content.mcpublish.ai/p/:slug" example, replace:

```ruby
    api_key = ApiKey.issue!(label: "Alice").first
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 5)
```

with:

```ruby
    user = User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123")
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5)
```

- [ ] **Step 13: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 14: Commit**

```bash
git add db/migrate app/models/artifact.rb app/models/api_key.rb app/models/user.rb app/services/mcp app/controllers/mcp_controller.rb spec/models/artifact_spec.rb spec/requests/mcp_tools_call_spec.rb spec/requests/content_spec.rb spec/requests/content_host_routing_spec.rb spec/requests/session_isolation_spec.rb db/schema.rb
git commit -m "Migrate artifact ownership from ApiKey to User"
```

---

## Task 2: Artifact Visibility & Organization Link

**Files:**
- Create: `db/migrate/<timestamp>_add_visibility_to_artifacts.rb`
- Modify: `app/models/artifact.rb`
- Modify: `app/models/organization.rb`
- Modify: `spec/models/artifact_spec.rb`
- Test: `spec/models/organization_spec.rb` (addition)

**Interfaces:**
- Consumes: `Organization` (existing, from the accounts/orgs plan).
- Produces: `Artifact::VISIBILITIES` (`%w[private organisation shared public]`); `Artifact#visibility`, `Artifact#organization`; `Organization#artifacts`.

- [ ] **Step 1: Write the failing spec additions**

Add to `spec/models/artifact_spec.rb`, inside the existing `RSpec.describe Artifact` block (after the last existing example):

```ruby
  it "defaults to private visibility" do
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.visibility).to eq("private")
  end

  it "rejects an invalid visibility value" do
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "bogus")
    expect(artifact).not_to be_valid
  end

  it "requires an organization when visibility is organisation" do
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "organisation")
    expect(artifact).not_to be_valid
  end

  it "accepts an organisation-visibility artifact with an organization set" do
    org = Organization.create!(name: "Acme", slug: "acme")
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "organisation", organization: org)
    expect(artifact).to be_valid
  end

  it "rejects an organization set on a non-organisation-visibility artifact" do
    org = Organization.create!(name: "Acme", slug: "acme")
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "private", organization: org)
    expect(artifact).not_to be_valid
  end
```

Add to `spec/models/organization_spec.rb`, inside the existing `RSpec.describe Organization` block:

```ruby
  it "is accessible via organization#artifacts" do
    org = Organization.create!(name: "Acme", slug: "acme")
    user = User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123")
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "organisation", organization: org)

    expect(org.artifacts).to include(artifact)
  end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/models/artifact_spec.rb spec/models/organization_spec.rb`
Expected: FAIL — `Artifact` has no `visibility`/`organization` attributes yet

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration AddVisibilityToArtifacts
```

Replace the generated file's contents with:

```ruby
class AddVisibilityToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :visibility, :string, null: false, default: "private"
    add_reference :artifacts, :organization, foreign_key: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Update the Artifact model**

Replace the full contents of `app/models/artifact.rb`:

```ruby
class Artifact < ApplicationRecord
  belongs_to :user
  belongs_to :organization, optional: true

  VISIBILITIES = %w[private organisation shared public].freeze

  validates :slug, presence: true, uniqueness: true
  validates :storage_key, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :organization, presence: true, if: -> { visibility == "organisation" }
  validate :no_organization_unless_organisation_visibility

  before_validation :assign_slug, on: :create

  def url
    "https://#{Rails.application.config.x.content_host}/p/#{slug}"
  end

  private

  def assign_slug
    self.slug ||= SlugGenerator.generate_unique
  end

  def no_organization_unless_organisation_visibility
    return unless organization.present? && visibility != "organisation"

    errors.add(:organization, "must be blank unless visibility is organisation")
  end
end
```

- [ ] **Step 5: Update the Organization model**

Replace the full contents of `app/models/organization.rb`:

```ruby
class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :organization_invites, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :artifacts, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+\z/, message: "may only contain lowercase letters, numbers, and hyphens" }
end
```

- [ ] **Step 6: Run the specs to verify they pass**

Run: `bundle exec rspec spec/models/artifact_spec.rb spec/models/organization_spec.rb`
Expected: PASS (11 + 6 examples)

- [ ] **Step 7: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 8: Commit**

```bash
git add db/migrate app/models/artifact.rb app/models/organization.rb spec/models/artifact_spec.rb spec/models/organization_spec.rb db/schema.rb
git commit -m "Add artifact visibility and organization link"
```

---

## Task 3: ArtifactShare Model & Signup Claiming

**Files:**
- Create: `db/migrate/<timestamp>_create_artifact_shares.rb`
- Create: `app/models/artifact_share.rb`
- Modify: `app/models/artifact.rb`
- Modify: `app/controllers/users_controller.rb`
- Test: `spec/models/artifact_share_spec.rb`
- Modify: `spec/requests/signup_spec.rb`

**Interfaces:**
- Consumes: `Artifact` (Task 2), `User` (existing), `UsersController#create`'s `claim_pending_invites` pattern (existing, from the accounts/orgs plan).
- Produces: `ArtifactShare` (`artifact`, `email`, nullable `user`); `Artifact#artifact_shares`. Claimed automatically at signup, same pattern as `OrganizationInvite`.

- [ ] **Step 1: Write the failing ArtifactShare spec**

Create `spec/models/artifact_share_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ArtifactShare do
  let(:user) { User.create!(email: "owner@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5) }

  it "requires a valid email" do
    share = ArtifactShare.new(artifact: artifact, email: "not-an-email")
    expect(share).not_to be_valid
  end

  it "normalizes email to lowercase" do
    share = ArtifactShare.create!(artifact: artifact, email: "Invitee@Example.com")
    expect(share.email).to eq("invitee@example.com")
  end

  it "is valid without a user (pending claim)" do
    share = ArtifactShare.new(artifact: artifact, email: "invitee@example.com")
    expect(share).to be_valid
  end

  it "prevents duplicate emails on the same artifact" do
    ArtifactShare.create!(artifact: artifact, email: "invitee@example.com")
    dupe = ArtifactShare.new(artifact: artifact, email: "invitee@example.com")

    expect(dupe).not_to be_valid
  end

  it "is destroyed when its artifact is destroyed" do
    share = ArtifactShare.create!(artifact: artifact, email: "invitee@example.com")
    artifact.destroy!

    expect(ArtifactShare.exists?(share.id)).to eq(false)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/artifact_share_spec.rb`
Expected: FAIL — `uninitialized constant ArtifactShare`

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration CreateArtifactShares
```

Replace the generated file's contents with:

```ruby
class CreateArtifactShares < ActiveRecord::Migration[8.0]
  def change
    create_table :artifact_shares do |t|
      t.references :artifact, null: false, foreign_key: true
      t.string :email, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :artifact_shares, [ :artifact_id, :email ], unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Write the ArtifactShare model**

Create `app/models/artifact_share.rb`:

```ruby
class ArtifactShare < ApplicationRecord
  belongs_to :artifact
  belongs_to :user, optional: true

  before_validation :normalize_email

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :artifact_id, case_sensitive: false }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
```

- [ ] **Step 5: Add the inverse association to Artifact**

In `app/models/artifact.rb`, add alongside the existing `belongs_to`/`validates` lines (as the first line inside the class, before `belongs_to :user`):

```ruby
  has_many :artifact_shares, dependent: :destroy
```

- [ ] **Step 6: Run the ArtifactShare spec to verify it passes**

Run: `bundle exec rspec spec/models/artifact_share_spec.rb`
Expected: PASS (5 examples)

- [ ] **Step 7: Write the failing signup-claims-shares spec**

Add to `spec/requests/signup_spec.rb`, as a new example inside the existing `RSpec.describe "Signup"` block:

```ruby
  it "claims any pending artifact shares matching the new user's email" do
    owner = User.create!(email: "owner@example.com", password: "password123", password_confirmation: "password123")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "shared")
    ArtifactShare.create!(artifact: artifact, email: "invitee@example.com")

    post "/signup", params: { user: { email: "invitee@example.com", password: "password123", password_confirmation: "password123" } }

    new_user = User.find_by!(email: "invitee@example.com")
    expect(ArtifactShare.find_by(artifact: artifact).user).to eq(new_user)
  end
```

- [ ] **Step 8: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: FAIL — the share is created but never claimed

- [ ] **Step 9: Wire share-claiming into UsersController#create**

In `app/controllers/users_controller.rb`, add a call to a new `claim_pending_shares` method inside the existing transaction block:

```ruby
    ActiveRecord::Base.transaction do
      @user.save!
      claim_pending_invites(@user)
      claim_pending_shares(@user)
    end
```

Add a new private method below `claim_pending_invites`:

```ruby
  def claim_pending_shares(user)
    ArtifactShare.where(email: user.email, user_id: nil).find_each do |share|
      share.update!(user: user)
    end
  end
```

- [ ] **Step 10: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/signup_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 11: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 12: Commit**

```bash
git add db/migrate app/models/artifact_share.rb app/models/artifact.rb app/controllers/users_controller.rb spec/models/artifact_share_spec.rb spec/requests/signup_spec.rb db/schema.rb
git commit -m "Add ArtifactShare model with signup-time claiming"
```

---

## Task 4: MCP Tool Visibility Params

**Files:**
- Create: `app/services/mcp/tools/organization_resolver.rb`
- Create: `app/services/mcp/tools/shared_with_applier.rb`
- Modify: `app/services/mcp/tools/publish_artifact.rb`
- Modify: `app/services/mcp/tools/update_artifact.rb`
- Modify: `app/services/mcp/tools/list_artifacts.rb`
- Modify: `app/services/mcp/tool_definitions.rb`
- Test: `spec/requests/mcp_tools_call_spec.rb` (additions)

**Interfaces:**
- Consumes: `Artifact::VISIBILITIES`, `ArtifactShare` (Tasks 2–3), `User#organizations` (existing).
- Produces: `Mcp::Tools::OrganizationResolver.resolve(user:, slug:)` → `Organization`, raises `ToolDispatcher::ToolError`; `Mcp::Tools::SharedWithApplier.apply(artifact:, emails:)` — replaces the artifact's full `ArtifactShare` set, raises `ToolDispatcher::ToolError` on an invalid email.

- [ ] **Step 1: Write the failing request specs**

Add to `spec/requests/mcp_tools_call_spec.rb`, inside the existing `describe "publish_artifact"` block (after the last existing example, before its closing `end`):

```ruby
    it "publishes with organisation visibility when the caller belongs to the organization" do
      org = Organization.create!(name: "Acme", slug: "acme")
      OrganizationMembership.create!(user: user, organization: org, role: "admin")

      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "organisation", organization: "acme" })

      artifact = Artifact.find_by(slug: result["result"]["slug"])
      expect(artifact.visibility).to eq("organisation")
      expect(artifact.organization).to eq(org)
    end

    it "rejects publishing with an organization the caller does not belong to" do
      Organization.create!(name: "Acme", slug: "acme")

      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "organisation", organization: "acme" })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "publishes with shared visibility and creates ArtifactShare rows" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "shared", shared_with: [ "invitee@example.com" ] })

      artifact = Artifact.find_by(slug: result["result"]["slug"])
      expect(artifact.visibility).to eq("shared")
      expect(artifact.artifact_shares.pluck(:email)).to eq([ "invitee@example.com" ])
    end

    it "rejects a malformed email in shared_with" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "shared", shared_with: [ "not-an-email" ] })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "rejects an invalid visibility value" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "bogus" })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end
```

Add to the existing `describe "update_artifact"` block (after the last existing example, before its closing `end`):

```ruby
    it "changes visibility without resending html" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>" })
      slug = publish_result["result"]["slug"]

      result = call_tool("update_artifact", { slug: slug, visibility: "public" })

      expect(result["result"]["isError"]).to be_nil
      expect(Artifact.find_by(slug: slug).visibility).to eq("public")
      expect(Artifact.find_by(slug: slug).byte_size).to eq("<html>v1</html>".bytesize)
    end

    it "replaces the full shared_with list rather than appending to it" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "shared", shared_with: [ "a@example.com", "b@example.com" ] })
      slug = publish_result["result"]["slug"]

      call_tool("update_artifact", { slug: slug, shared_with: [ "b@example.com" ] })

      expect(Artifact.find_by(slug: slug).artifact_shares.pluck(:email)).to eq([ "b@example.com" ])
    end

    it "clears the organization when switching away from organisation visibility" do
      org = Organization.create!(name: "Acme", slug: "acme")
      OrganizationMembership.create!(user: user, organization: org, role: "admin")
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "organisation", organization: "acme" })
      slug = publish_result["result"]["slug"]

      call_tool("update_artifact", { slug: slug, visibility: "private" })

      expect(Artifact.find_by(slug: slug).organization).to be_nil
    end

    it "clears artifact_shares when switching away from shared visibility" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "shared", shared_with: [ "a@example.com" ] })
      slug = publish_result["result"]["slug"]

      call_tool("update_artifact", { slug: slug, visibility: "private" })

      expect(Artifact.find_by(slug: slug).artifact_shares).to be_empty
    end
```

Add to the existing `describe "list_artifacts"` block (after the last existing example, before its closing `end`):

```ruby
    it "includes visibility, organization, and shared_with for each artifact" do
      org = Organization.create!(name: "Acme", slug: "acme")
      OrganizationMembership.create!(user: user, organization: org, role: "admin")
      call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "organisation", organization: "acme" })

      result = call_tool("list_artifacts", {})

      artifact_data = result["result"]["artifacts"].first
      expect(artifact_data["visibility"]).to eq("organisation")
      expect(artifact_data["organization"]).to eq("acme")
      expect(artifact_data["shared_with"]).to eq([])
    end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: FAIL — the tools don't accept `visibility`/`organization`/`shared_with` yet

- [ ] **Step 3: Write the shared helper classes**

Create `app/services/mcp/tools/organization_resolver.rb`:

```ruby
module Mcp
  module Tools
    module OrganizationResolver
      module_function

      def resolve(user:, slug:)
        organization = user.organizations.find_by(slug: slug)
        raise ToolDispatcher::ToolError, "Organization not found: #{slug}" unless organization

        organization
      end
    end
  end
end
```

Create `app/services/mcp/tools/shared_with_applier.rb`:

```ruby
module Mcp
  module Tools
    module SharedWithApplier
      module_function

      # Replaces the artifact's full ArtifactShare set with one row per
      # email — this is how a share is revoked: resend the list without
      # that person.
      def apply(artifact:, emails:)
        artifact.artifact_shares.destroy_all

        emails.each do |raw_email|
          email = raw_email.to_s.strip.downcase
          unless email.match?(URI::MailTo::EMAIL_REGEXP)
            raise ToolDispatcher::ToolError, "Invalid email in shared_with: #{raw_email}"
          end

          share = artifact.artifact_shares.find_or_initialize_by(email: email)
          share.user = User.find_by(email: email)
          share.save!
        end
      end
    end
  end
end
```

- [ ] **Step 4: Update PublishArtifact**

Replace the full contents of `app/services/mcp/tools/publish_artifact.rb`:

```ruby
module Mcp
  module Tools
    class PublishArtifact
      MAX_BYTES = 5.megabytes
      MAX_SLUG_ATTEMPTS = 3

      def initialize(user:, arguments:)
        @user = user
        @html = arguments["html"]
        @visibility = arguments["visibility"] || "private"
        @organization_slug = arguments["organization"]
        @shared_with = arguments["shared_with"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end
        unless Artifact::VISIBILITIES.include?(@visibility)
          raise ToolDispatcher::ToolError, "Invalid visibility: #{@visibility}"
        end

        organization = @visibility == "organisation" ? OrganizationResolver.resolve(user: @user, slug: @organization_slug) : nil

        artifact = create_artifact_with_retry(organization)

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        SharedWithApplier.apply(artifact: artifact, emails: @shared_with) if @visibility == "shared" && @shared_with.present?

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end

      private

      # SlugGenerator checks Artifact.exists? before the caller inserts, so two
      # concurrent publishes can both pass that check for the same slug before
      # either commits — the DB's unique index then rejects the loser. Retry
      # with a freshly-generated slug rather than surfacing a raw DB error.
      def create_artifact_with_retry(organization)
        attempts = 0
        begin
          attempts += 1
          artifact = Artifact.new(
            user: @user,
            storage_key: "artifacts/#{SecureRandom.uuid}",
            byte_size: @html.bytesize,
            visibility: @visibility,
            organization: organization
          )
          artifact.save!
          artifact
        rescue ActiveRecord::RecordNotUnique
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.errors.of_kind?(:slug, :taken)
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        end
      end
    end
  end
end
```

- [ ] **Step 5: Update UpdateArtifact**

Replace the full contents of `app/services/mcp/tools/update_artifact.rb`:

```ruby
module Mcp
  module Tools
    class UpdateArtifact
      MAX_BYTES = Mcp::Tools::PublishArtifact::MAX_BYTES
      NOT_FOUND_MESSAGE = "Artifact not found".freeze

      def initialize(user:, arguments:)
        @user = user
        @slug = arguments["slug"]
        @html = arguments["html"]
        @visibility = arguments["visibility"]
        @organization_slug = arguments["organization"]
        @shared_with = arguments["shared_with"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: slug" if @slug.blank?
        if @html.present? && @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end
        if @visibility && !Artifact::VISIBILITIES.include?(@visibility)
          raise ToolDispatcher::ToolError, "Invalid visibility: #{@visibility}"
        end

        artifact = @user.artifacts.find_by(slug: @slug)
        raise ToolDispatcher::ToolError, NOT_FOUND_MESSAGE unless artifact

        if @html.present?
          begin
            ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
          rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
            raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
          end
        end

        apply_updates(artifact)

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end

      private

      def apply_updates(artifact)
        attributes = {}
        attributes[:byte_size] = @html.bytesize if @html.present?

        if @visibility
          attributes[:visibility] = @visibility
          attributes[:organization] =
            @visibility == "organisation" ? OrganizationResolver.resolve(user: @user, slug: @organization_slug) : nil
        end

        artifact.update!(attributes) if attributes.any?

        artifact.artifact_shares.destroy_all if @visibility && @visibility != "shared"
        SharedWithApplier.apply(artifact: artifact, emails: @shared_with) if @shared_with
      end
    end
  end
end
```

- [ ] **Step 6: Update ListArtifacts**

Replace the full contents of `app/services/mcp/tools/list_artifacts.rb`:

```ruby
module Mcp
  module Tools
    class ListArtifacts
      def initialize(user:, arguments:)
        @user = user
      end

      def call
        artifacts = @user.artifacts.order(created_at: :desc).map do |artifact|
          {
            slug: artifact.slug,
            url: artifact.url,
            byte_size: artifact.byte_size,
            visibility: artifact.visibility,
            organization: artifact.organization&.slug,
            shared_with: artifact.artifact_shares.pluck(:email),
            created_at: artifact.created_at.iso8601,
            updated_at: artifact.updated_at.iso8601
          }
        end

        { content: [ { type: "text", text: "#{artifacts.size} artifact(s)" } ], artifacts: artifacts }
      end
    end
  end
end
```

- [ ] **Step 7: Update the tool schema definitions**

Replace the full contents of `app/services/mcp/tool_definitions.rb`:

```ruby
module Mcp
  module ToolDefinitions
    VISIBILITY_PROPERTIES = {
      visibility: {
        type: "string",
        enum: %w[private organisation shared public],
        description: "Who can view this artifact. Defaults to private."
      },
      organization: {
        type: "string",
        description: "Organization slug — required when visibility is organisation. Must be an organization you belong to."
      },
      shared_with: {
        type: "array",
        items: { type: "string" },
        description: "Email addresses to share with — used when visibility is shared. Replaces the full share list."
      }
    }.freeze

    ALL = [
      {
        name: "publish_artifact",
        description: "Publish a new self-contained HTML artifact and get back a public URL.",
        inputSchema: {
          type: "object",
          properties: {
            html: { type: "string", description: "Self-contained HTML content to publish." }
          }.merge(VISIBILITY_PROPERTIES),
          required: [ "html" ]
        }
      },
      {
        name: "update_artifact",
        description: "Update a previously published artifact's content and/or visibility, keeping its URL.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to update." },
            html: { type: "string", description: "New HTML content. Omit to change only visibility." }
          }.merge(VISIBILITY_PROPERTIES),
          required: [ "slug" ]
        }
      },
      {
        name: "list_artifacts",
        description: "List all artifacts published with this API key.",
        inputSchema: { type: "object", properties: {} }
      },
      {
        name: "delete_artifact",
        description: "Delete a previously published artifact.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to delete." }
          },
          required: [ "slug" ]
        }
      }
    ].freeze
  end
end
```

- [ ] **Step 8: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: PASS (24 examples)

- [ ] **Step 9: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 10: Commit**

```bash
git add app/services/mcp spec/requests/mcp_tools_call_spec.rb
git commit -m "Add visibility, organization, and shared_with params to MCP tools"
```

---

## Task 5: Signed Content-Access Tokens

**Files:**
- Create: `app/services/content_access_token.rb`
- Test: `spec/services/content_access_token_spec.rb`

**Interfaces:**
- Produces: `ContentAccessToken.generate(artifact:, user:)` → signed token string; `ContentAccessToken.verify(token, slug:)` → payload hash (`:artifact_id`, `:user_id`, `:slug`, `:expires_at`) or `nil` for any invalid/expired/mismatched/missing token. Later tasks (6–7) mint tokens at the view-authorization endpoint and verify them in `ContentController`.

- [ ] **Step 1: Write the failing spec**

Create `spec/services/content_access_token_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ContentAccessToken do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5, slug: "abcd1234") }

  it "generates a token that verifies for the same slug" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    payload = ContentAccessToken.verify(token, slug: artifact.slug)

    expect(payload[:artifact_id]).to eq(artifact.id)
    expect(payload[:user_id]).to eq(user.id)
  end

  it "rejects a token verified against a different slug" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    expect(ContentAccessToken.verify(token, slug: "different-slug")).to be_nil
  end

  it "rejects a tampered token" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    expect(ContentAccessToken.verify(token + "x", slug: artifact.slug)).to be_nil
  end

  it "rejects a blank token" do
    expect(ContentAccessToken.verify(nil, slug: artifact.slug)).to be_nil
    expect(ContentAccessToken.verify("", slug: artifact.slug)).to be_nil
  end

  it "rejects an expired token" do
    token = nil
    travel_to 2.hours.ago do
      token = ContentAccessToken.generate(artifact: artifact, user: user)
    end

    expect(ContentAccessToken.verify(token, slug: artifact.slug)).to be_nil
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/content_access_token_spec.rb`
Expected: FAIL — `uninitialized constant ContentAccessToken`

- [ ] **Step 3: Write ContentAccessToken**

Create `app/services/content_access_token.rb`:

```ruby
class ContentAccessToken
  EXPIRY = 1.hour

  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base, digest: "SHA256")
  end

  def self.generate(artifact:, user:)
    verifier.generate(
      { artifact_id: artifact.id, user_id: user.id, slug: artifact.slug, expires_at: EXPIRY.from_now.to_i },
      purpose: :content_access
    )
  end

  # Returns the decoded payload hash if the token is valid, unexpired, and
  # names this exact slug — nil for any other reason (missing, tampered,
  # expired, or minted for a different artifact). Callers should treat nil
  # identically to "no token at all", never as a distinct error.
  def self.verify(token, slug:)
    return nil if token.blank?

    payload = verifier.verify(token, purpose: :content_access)
    return nil if payload[:expires_at] < Time.current.to_i
    return nil if payload[:slug] != slug

    payload
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/content_access_token_spec.rb`
Expected: PASS (5 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/content_access_token.rb spec/services/content_access_token_spec.rb
git commit -m "Add signed, short-lived content-access tokens"
```

---

## Task 6: View-Authorization Endpoint

**Files:**
- Create: `app/controllers/artifacts_controller.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/artifacts_view_spec.rb`

**Interfaces:**
- Consumes: `ContentAccessToken` (Task 5), `Artifact#visibility`/`#organization`/`#artifact_shares` (Tasks 2–3), `Authenticatable#current_user` (existing).
- Produces: `GET /artifacts/:slug/view` (`view_artifact_path`) — the main-app endpoint that makes the actual permission decision and redirects to the content host with a token, or renders the generic not-found. `SessionsController#create` now honors a `session[:return_to]` set by this endpoint.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/artifacts_view_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Artifact view authorization", type: :request do
  let(:owner) { User.create!(email: "owner@example.com", password: "password123", password_confirmation: "password123") }
  let(:stranger) { User.create!(email: "stranger@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "redirects to login when signed out, preserving the return path" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to redirect_to("/login")
  end

  it "redirects the owner back to the login-preserved path after signing in" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")

    get "/artifacts/#{artifact.slug}/view"
    post "/login", params: { email: owner.email, password: "password123" }

    expect(response).to redirect_to("/artifacts/#{artifact.slug}/view")
  end

  it "grants the owner a signed content-access token and redirects to the content host" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(owner)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
    location = URI.parse(response.headers["Location"])
    expect(location.host).to eq("content.mcpublish.ai")
    expect(location.path).to eq("/p/#{artifact.slug}")
    expect(Rack::Utils.parse_query(location.query)).to have_key("token")
  end

  it "returns the generic not-found for a stranger on a private artifact" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "returns the identical response for a nonexistent slug and a forbidden one" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"
    forbidden_body = response.body

    get "/artifacts/nosuchslug/view"
    missing_body = response.body

    expect(forbidden_body).to eq(missing_body)
    expect(response).to have_http_status(:not_found)
  end

  it "grants access to an organisation member" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    member = User.create!(email: "member@example.com", password: "password123", password_confirmation: "password123")
    OrganizationMembership.create!(user: member, organization: org, role: "member")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(member)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end

  it "denies a non-member on an organisation artifact" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "revokes access dynamically when a member is removed from the organisation" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    membership = OrganizationMembership.create!(user: stranger, organization: org, role: "member")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"
    expect(response).to have_http_status(:found)

    membership.destroy!

    get "/artifacts/#{artifact.slug}/view"
    expect(response).to have_http_status(:not_found)
  end

  it "grants access to a shared user" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "shared")
    ArtifactShare.create!(artifact: artifact, email: stranger.email, user: stranger)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end

  it "denies a user not on the share list" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "shared")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "grants access to a public artifact reached directly" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "public")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/artifacts_view_spec.rb`
Expected: FAIL — no route matches `GET /artifacts/:slug/view`

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the existing `constraints(->(req) { !on_content_host.call(req) }) do ... end` block, add after the `resources :organizations` block:

```ruby
    get "/artifacts/:slug/view", to: "artifacts#view", as: :view_artifact
```

- [ ] **Step 4: Write ArtifactsController**

Create `app/controllers/artifacts_controller.rb`:

```ruby
class ArtifactsController < WebController
  def view
    artifact = Artifact.find_by(slug: params[:slug])

    unless current_user
      session[:return_to] = request.fullpath
      redirect_to login_path, alert: "Please log in first"
      return
    end

    if artifact.nil? || !permitted?(artifact)
      render_not_found
      return
    end

    token = ContentAccessToken.generate(artifact: artifact, user: current_user)
    redirect_to "https://#{Rails.application.config.x.content_host}/p/#{artifact.slug}?token=#{CGI.escape(token)}",
      allow_other_host: true
  end

  private

  def permitted?(artifact)
    return true if artifact.visibility == "public"
    return true if artifact.user_id == current_user.id
    return true if artifact.visibility == "organisation" && current_user.organizations.exists?(id: artifact.organization_id)
    return true if artifact.visibility == "shared" && artifact.artifact_shares.exists?(user_id: current_user.id)

    false
  end

  def render_not_found
    render plain: "Not found", status: :not_found
  end
end
```

- [ ] **Step 5: Wire return-to into SessionsController**

In `app/controllers/sessions_controller.rb`, replace the `create` method:

```ruby
  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      return_to = session[:return_to]
      reset_session
      session[:user_id] = user.id
      redirect_to (return_to || account_path), notice: "Signed in"
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/artifacts_view_spec.rb`
Expected: PASS (11 examples)

- [ ] **Step 7: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples (in particular, re-check `spec/requests/login_logout_spec.rb` — the return-to change must not affect the plain login-with-no-pending-return-to case)

- [ ] **Step 8: Commit**

```bash
git add app/controllers/artifacts_controller.rb app/controllers/sessions_controller.rb config/routes.rb spec/requests/artifacts_view_spec.rb
git commit -m "Add the main-app view-authorization endpoint for gated artifacts"
```

---

## Task 7: Gate Content Serving on Non-Public Artifacts

**Files:**
- Modify: `app/controllers/content_controller.rb`
- Modify: `config/initializers/content_host.rb`
- Modify: `spec/requests/content_spec.rb`
- Modify: `spec/requests/content_host_routing_spec.rb`
- Modify: `spec/requests/session_isolation_spec.rb`

**Interfaces:**
- Consumes: `ContentAccessToken.verify` (Task 5), `Artifact#visibility` (Task 2).
- Produces: `GET content.mcpublish.ai/p/:slug` now serves `public` artifacts directly (unchanged), and redirects everything else (gated artifacts and nonexistent slugs alike) to `mcpublish.ai/artifacts/:slug/view` unless a valid, slug-matching token is present.

- [ ] **Step 1: Add a main-host config value**

`ArtifactsController#view` already knows the content host; `ContentController` now needs to know the *main* app's host to redirect to, without deriving it by string-manipulating `content_host` (fragile). Replace the full contents of `config/initializers/content_host.rb`:

```ruby
Rails.application.config.x.content_host =
  ENV.fetch("CONTENT_HOST", "content.mcpublish.ai").to_s.strip.downcase.delete_suffix(".")

Rails.application.config.x.main_host =
  ENV.fetch("MAIN_HOST", "mcpublish.ai").to_s.strip.downcase.delete_suffix(".")
```

- [ ] **Step 2: Write the failing content-serving specs**

Replace the full contents of `spec/requests/content_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Content serving", type: :request do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 20, visibility: "public") }

  before do
    ArtifactStorage.client.stub_responses(:get_object, body: "<html>hello</html>")
    host! "content.mcpublish.ai"
  end

  it "serves the artifact's html" do
    get "/p/#{artifact.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<html>hello</html>")
    expect(response.content_type).to include("text/html")
  end

  it "sets no Set-Cookie header" do
    get "/p/#{artifact.slug}"
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "disables caching so updates via update_artifact are reflected immediately" do
    get "/p/#{artifact.slug}"
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "redirects to the view-authorization flow for an unknown slug" do
    get "/p/nosuchslug"
    expect(response).to redirect_to("https://mcpublish.ai/artifacts/nosuchslug/view")
  end

  it "returns 404 when the S3 object is missing despite a valid public record" do
    ArtifactStorage.client.stub_responses(:get_object, "NoSuchKey")
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "is not routable on the main app host" do
    host! "mcpublish.ai"
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "redirects to the view-authorization flow when the artifact is private and no token is given" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")

    get "/p/#{private_artifact.slug}"

    expect(response).to redirect_to("https://mcpublish.ai/artifacts/#{private_artifact.slug}/view")
  end

  it "serves a private artifact when a valid token is given" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")
    token = ContentAccessToken.generate(artifact: private_artifact, user: user)

    get "/p/#{private_artifact.slug}", params: { token: token }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<html>hello</html>")
  end

  it "redirects instead of serving when the token is for a different slug" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")
    other_artifact = Artifact.create!(user: user, storage_key: "artifacts/3", byte_size: 5, visibility: "private")
    token = ContentAccessToken.generate(artifact: other_artifact, user: user)

    get "/p/#{private_artifact.slug}", params: { token: token }

    expect(response).to redirect_to("https://mcpublish.ai/artifacts/#{private_artifact.slug}/view")
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: FAIL — unknown/private slugs currently 404 directly instead of redirecting

- [ ] **Step 4: Update ContentController**

Replace the full contents of `app/controllers/content_controller.rb`:

```ruby
# Inherits ActionController::API directly (not ApplicationController).
# Session/cookie middleware is global to the Rack stack (it has to be, to
# support the web UI), so middleware absence alone no longer keeps this
# controller session-free. The `session` override below is the actual
# guard: it raises immediately if session is ever touched here, turning a
# future violation into a hard failure instead of a silent possibility.
#
# This controller never makes a permission decision. It only knows two
# things: is this artifact public (serve it), or is there a valid,
# slug-matching signed token (serve it) — anything else redirects to the
# main app's view-authorization endpoint, which does have a session and
# makes the actual call. That includes a nonexistent slug: routing both
# "doesn't exist" and "exists but forbidden" through the same endpoint is
# what gives them an identical response.
class ContentController < ActionController::API
  def show
    artifact = Artifact.find_by(slug: params[:slug])

    if artifact&.visibility == "public"
      serve(artifact)
      return
    end

    payload = artifact && ContentAccessToken.verify(params[:token], slug: params[:slug])
    if payload && payload[:artifact_id] == artifact.id
      serve(artifact)
      return
    end

    redirect_to "https://#{Rails.application.config.x.main_host}/artifacts/#{params[:slug]}/view",
      allow_other_host: true
  end

  private

  def serve(artifact)
    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: html, content_type: "text/html"
  end

  def session
    raise "ContentController must never access the session"
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: PASS (9 examples)

- [ ] **Step 6: Update the remaining specs that create artifacts expecting direct serving**

In `spec/requests/content_host_routing_spec.rb`, in the first example's `Artifact.create!` call, add `visibility: "public"`:

```ruby
      artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 20, visibility: "public")
```

Apply the same `visibility: "public"` addition to the second example's `Artifact.create!` call.

In `spec/requests/session_isolation_spec.rb`, in the "does not set a cookie on GET content.mcpublish.ai/p/:slug" example, add `visibility: "public"`:

```ruby
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5, visibility: "public")
```

- [ ] **Step 7: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 8: Commit**

```bash
git add app/controllers/content_controller.rb config/initializers/content_host.rb spec/requests/content_spec.rb spec/requests/content_host_routing_spec.rb spec/requests/session_isolation_spec.rb
git commit -m "Gate content serving on visibility, using signed tokens for non-public artifacts"
```
