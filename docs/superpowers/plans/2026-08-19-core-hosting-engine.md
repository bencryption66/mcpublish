# Core Hosting Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Rails app exposing an MCP server that lets an authenticated agent publish, update, list, and delete single-file HTML artifacts, served back from an origin-isolated subdomain.

**Architecture:** One Rails 8 API-only app. `POST /mcp` on the main host handles the MCP JSON-RPC protocol (hand-rolled — no third-party MCP gem, so behavior stays fully within code this plan defines and tests, rather than depending on an unverified library API). `GET /p/:slug` on the `content` subdomain, served by a controller that inherits directly from `ActionController::API` (never `ApplicationController`) so it can never pick up session/cookie middleware regardless of what the main app gains later. Artifact metadata lives in Postgres; artifact HTML bytes live in S3.

**Tech Stack:** Ruby (3.3+), Rails 8 (`--api` mode), PostgreSQL, RSpec (request/model specs — no FactoryBot; the model set is small enough that plain `ApiKey.issue!` / `Artifact.create!` calls in specs are simpler), `aws-sdk-s3`, `rack-attack`.

**Out of scope for this plan:** AWS infrastructure provisioning (ECS task definitions, RDS instance, S3 bucket creation, DNS + TLS for `content.mcpublish.ai`). This plan produces a working, fully-tested Rails app runnable locally; standing up the actual AWS resources is a separate infra task once the app is verified.

## Global Constraints

- Artifact size cap: **5MB** per `publish_artifact` / `update_artifact` call.
- Rate limit: **~30 `publish_artifact`/`update_artifact` calls per minute per API key** (other MCP methods are not rate-limited).
- Slugs are **always server-generated** (random, ~8 characters); no agent-suggested slugs.
- `update_artifact` / `delete_artifact` on a not-found slug and on a not-owned slug return the **identical generic error message** (no existence leak).
- Content responses (`GET content.mcpublish.ai/p/:slug`) are served **without long-lived caching** and **without any `Set-Cookie` header**.
- Content-serving controller must not inherit from a controller that could ever gain session middleware — inherit `ActionController::API` directly.
- MCP transport is Streamable HTTP (`POST /mcp`), JSON-RPC 2.0 envelope.

---

## Task 1: Rails App Scaffold

**Files:**
- Create: entire Rails app skeleton (via `rails new`), in the current project root
- Modify: `Gemfile`
- Test: `spec/requests/health_spec.rb`

**Interfaces:**
- Produces: a bootable Rails 8 API app with RSpec configured, used as the foundation for every later task.

- [ ] **Step 1: Generate the Rails app**

Run from your current project root — i.e. wherever this `docs/` directory and the git repo live (a worktree checkout, if you're working in one; do not run this in any other checkout of the same repo). `rails new .` will detect the existing `.git` and skip re-initializing it:

```bash
rails new . --api --database=postgresql --skip-test
```

- [ ] **Step 2: Add gems needed by later tasks**

Add to `Gemfile` (after the default `gem "pg"` line Rails already added):

```ruby
gem "aws-sdk-s3"
gem "rack-attack"

group :development, :test do
  gem "rspec-rails"
end
```

Run:

```bash
bundle install
```

- [ ] **Step 3: Install RSpec**

```bash
rails generate rspec:install
```

Expected: creates `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

- [ ] **Step 4: Create the database**

Requires a local PostgreSQL server running and reachable with the default credentials in the generated `config/database.yml` (adjust it or set `DATABASE_URL` if your local Postgres needs a username/password).

```bash
rails db:create
```

- [ ] **Step 5: Write a smoke test for the default health endpoint**

Rails 7.1+ apps include a default `GET /up` health check route out of the box. Write a request spec confirming the app boots and responds:

Create `spec/requests/health_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "responds with 200 OK" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 6: Run the test to confirm the scaffold works**

Run: `bundle exec rspec spec/requests/health_spec.rb`
Expected: PASS (this is a scaffold sanity check, not a red/green TDD cycle — there's no application code to write yet, just confirming the generated app boots and connects to Postgres).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold Rails 8 API app with RSpec"
```

---

## Task 2: ApiKey Model

**Files:**
- Create: `db/migrate/<timestamp>_create_api_keys.rb`
- Create: `app/models/api_key.rb`
- Create: `lib/tasks/api_keys.rake`
- Test: `spec/models/api_key_spec.rb`

**Interfaces:**
- Produces: `ApiKey.issue!(label:)` → `[api_key, raw_token]`; `ApiKey.authenticate(raw_token)` → `ApiKey` or `nil`; `ApiKey#revoked?` → boolean. Later tasks use `ApiKey.authenticate` for MCP request auth and `ApiKey#artifacts` (added in Task 3) for ownership scoping.

- [ ] **Step 1: Write the failing model spec**

Create `spec/models/api_key_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ApiKey, type: :model do
  describe ".issue!" do
    it "creates an api key and returns it with a raw token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(api_key).to be_persisted
      expect(api_key.label).to eq("Alice")
      expect(raw_token).to start_with("mcpub_")
    end

    it "does not store the raw token anywhere retrievable" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(api_key.token_digest).not_to eq(raw_token)
    end
  end

  describe ".authenticate" do
    it "returns the matching api key for a valid raw token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(ApiKey.authenticate(raw_token)).to eq(api_key)
    end

    it "returns nil for an unknown token" do
      expect(ApiKey.authenticate("mcpub_does_not_exist")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(ApiKey.authenticate(nil)).to be_nil
      expect(ApiKey.authenticate("")).to be_nil
    end

    it "returns nil for a revoked key's token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")
      api_key.update!(revoked_at: Time.current)

      expect(ApiKey.authenticate(raw_token)).to be_nil
    end
  end

  describe "#revoked?" do
    it "is false when revoked_at is nil" do
      api_key, = ApiKey.issue!(label: "Alice")
      expect(api_key.revoked?).to eq(false)
    end

    it "is true when revoked_at is set" do
      api_key, = ApiKey.issue!(label: "Alice")
      api_key.update!(revoked_at: Time.current)
      expect(api_key.revoked?).to eq(true)
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/api_key_spec.rb`
Expected: FAIL — `uninitialized constant ApiKey`

- [ ] **Step 3: Generate and write the migration**

```bash
rails generate migration CreateApiKeys
```

This creates `db/migrate/<timestamp>_create_api_keys.rb`. Replace its contents with:

```ruby
class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.string :token_digest, null: false
      t.string :label, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
rails db:migrate
```

- [ ] **Step 5: Write the model**

Create `app/models/api_key.rb`:

```ruby
class ApiKey < ApplicationRecord
  TOKEN_PREFIX = "mcpub_".freeze

  validates :label, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def self.issue!(label:)
    raw_token = TOKEN_PREFIX + SecureRandom.hex(32)
    api_key = create!(label: label, token_digest: digest(raw_token))
    [api_key, raw_token]
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

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/api_key_spec.rb`
Expected: PASS (8 examples)

- [ ] **Step 7: Add the manual issuance rake task**

Create `lib/tasks/api_keys.rake`:

```ruby
namespace :api_keys do
  desc "Issue a new API key: rails api_keys:issue[label]"
  task :issue, [:label] => :environment do |_task, args|
    label = args[:label]
    abort "Usage: rails api_keys:issue[label]" if label.blank?

    _api_key, raw_token = ApiKey.issue!(label: label)

    puts "API key issued for #{label.inspect}:"
    puts raw_token
    puts "(This token will not be shown again — store it now.)"
  end
end
```

- [ ] **Step 8: Manually verify the rake task**

Run: `rails api_keys:issue[test-user]`
Expected output: three lines — a confirmation line, a token starting with `mcpub_`, and the "will not be shown again" note. Then confirm it's usable:

Run: `rails runner 'puts ApiKey.last.label'`
Expected: `test-user`

- [ ] **Step 9: Commit**

```bash
git add db/migrate app/models/api_key.rb lib/tasks/api_keys.rake spec/models/api_key_spec.rb db/schema.rb
git commit -m "Add ApiKey model with manual issuance"
```

---

## Task 3: Artifact Model

**Files:**
- Create: `db/migrate/<timestamp>_create_artifacts.rb`
- Create: `app/services/slug_generator.rb`
- Create: `app/models/artifact.rb`
- Modify: `app/models/api_key.rb`
- Test: `spec/services/slug_generator_spec.rb`
- Test: `spec/models/artifact_spec.rb`

**Interfaces:**
- Consumes: `ApiKey` (Task 2).
- Produces: `SlugGenerator.generate_unique` → String; `Artifact#url` → String; `Artifact` has `slug`, `api_key_id`, `storage_key`, `byte_size`; `ApiKey#artifacts` association. Later tasks create/query `Artifact` scoped via `api_key.artifacts`.

- [ ] **Step 1: Write the failing SlugGenerator spec**

Create `spec/services/slug_generator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SlugGenerator do
  describe ".generate_unique" do
    it "returns an 8-character alphanumeric string" do
      slug = SlugGenerator.generate_unique
      expect(slug).to match(/\A[a-zA-Z0-9]{8}\z/)
    end

    it "does not return a slug already used by an existing artifact" do
      api_key, = ApiKey.issue!(label: "Alice")
      taken_slug = SlugGenerator.generate_unique
      Artifact.create!(api_key: api_key, slug: taken_slug, storage_key: "artifacts/1", byte_size: 10)

      allow(SlugGenerator).to receive(:candidate).and_return(taken_slug, "freshone1")

      expect(SlugGenerator.generate_unique).to eq("freshone1")
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/slug_generator_spec.rb`
Expected: FAIL — `uninitialized constant SlugGenerator` (and `Artifact` doesn't exist yet either)

- [ ] **Step 3: Generate and write the artifacts migration**

```bash
rails generate migration CreateArtifacts
```

Replace the generated file's contents with:

```ruby
class CreateArtifacts < ActiveRecord::Migration[8.0]
  def change
    create_table :artifacts do |t|
      t.string :slug, null: false
      t.references :api_key, null: false, foreign_key: true
      t.string :storage_key, null: false
      t.integer :byte_size, null: false

      t.timestamps
    end

    add_index :artifacts, :slug, unique: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Write SlugGenerator**

Create `app/services/slug_generator.rb`:

```ruby
class SlugGenerator
  ALPHABET = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
  LENGTH = 8
  MAX_ATTEMPTS = 5

  def self.generate_unique
    MAX_ATTEMPTS.times do
      slug = candidate
      return slug unless Artifact.exists?(slug: slug)
    end

    raise "Unable to generate a unique slug after #{MAX_ATTEMPTS} attempts"
  end

  def self.candidate
    Array.new(LENGTH) { ALPHABET.sample }.join
  end
end
```

- [ ] **Step 5: Write the Artifact model**

Create `app/models/artifact.rb`:

```ruby
class Artifact < ApplicationRecord
  belongs_to :api_key

  validates :slug, presence: true, uniqueness: true
  validates :storage_key, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }

  before_validation :assign_slug, on: :create

  def url
    "https://content.mcpublish.ai/p/#{slug}"
  end

  private

  def assign_slug
    self.slug ||= SlugGenerator.generate_unique
  end
end
```

Add the inverse association to `app/models/api_key.rb` — insert as the first line inside the class, before the `TOKEN_PREFIX` constant:

```ruby
  has_many :artifacts, dependent: :destroy
```

- [ ] **Step 6: Run the SlugGenerator spec to verify it passes**

Run: `bundle exec rspec spec/services/slug_generator_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 7: Write the failing Artifact model spec**

Create `spec/models/artifact_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Artifact, type: :model do
  let(:api_key) { ApiKey.issue!(label: "Alice").first }

  it "auto-assigns a slug on create" do
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to match(/\A[a-zA-Z0-9]{8}\z/)
  end

  it "does not overwrite an explicitly-set slug" do
    artifact = Artifact.create!(api_key: api_key, slug: "custom01", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to eq("custom01")
  end

  it "builds a content URL from the slug" do
    artifact = Artifact.create!(api_key: api_key, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://content.mcpublish.ai/p/abcd1234")
  end

  it "requires a positive byte_size" do
    artifact = Artifact.new(api_key: api_key, storage_key: "artifacts/1", byte_size: 0)
    expect(artifact).not_to be_valid
  end

  it "is accessible via api_key#artifacts" do
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 10)
    expect(api_key.artifacts).to include(artifact)
  end
end
```

- [ ] **Step 8: Run the spec to verify it fails, then passes**

Run: `bundle exec rspec spec/models/artifact_spec.rb`
Expected first: FAIL if any of the above wiring is missing — since Steps 4–5 already wrote the implementation, this should actually PASS (5 examples). If it fails, fix the model/migration before proceeding.

- [ ] **Step 9: Commit**

```bash
git add db/migrate app/services/slug_generator.rb app/models/artifact.rb app/models/api_key.rb spec/services/slug_generator_spec.rb spec/models/artifact_spec.rb db/schema.rb
git commit -m "Add Artifact model with server-generated slugs"
```

---

## Task 4: ArtifactStorage S3 Service

**Files:**
- Create: `config/initializers/aws.rb`
- Create: `app/services/artifact_storage.rb`
- Test: `spec/services/artifact_storage_spec.rb`

**Interfaces:**
- Produces: `ArtifactStorage.put(storage_key:, content:)`; `ArtifactStorage.get(storage_key:)` → String or `nil`; `ArtifactStorage.delete(storage_key:)`. Used by the MCP tool classes in Task 6 and the content controller in Task 7.

- [ ] **Step 1: Configure the AWS SDK for test/dev**

Create `config/initializers/aws.rb`:

```ruby
if Rails.env.test?
  Aws.config.update(stub_responses: true, region: "us-east-1")
else
  Aws.config.update(region: ENV.fetch("AWS_REGION", "us-east-1"))
end
```

- [ ] **Step 2: Write the failing ArtifactStorage spec**

Create `spec/services/artifact_storage_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ArtifactStorage do
  describe ".put" do
    it "uploads the content to the configured bucket with the given key" do
      client = ArtifactStorage.client
      client.stub_responses(:put_object, {})

      expect(client).to receive(:put_object).with(
        hash_including(bucket: ArtifactStorage::BUCKET, key: "artifacts/abc", body: "<html></html>", content_type: "text/html")
      ).and_call_original

      ArtifactStorage.put(storage_key: "artifacts/abc", content: "<html></html>")
    end
  end

  describe ".get" do
    it "returns the stored content for an existing key" do
      ArtifactStorage.client.stub_responses(:get_object, body: "<html>hi</html>")

      expect(ArtifactStorage.get(storage_key: "artifacts/abc")).to eq("<html>hi</html>")
    end

    it "returns nil when the key does not exist" do
      ArtifactStorage.client.stub_responses(:get_object, "NoSuchKey")

      expect(ArtifactStorage.get(storage_key: "artifacts/missing")).to be_nil
    end
  end

  describe ".delete" do
    it "deletes the object at the given key" do
      client = ArtifactStorage.client
      client.stub_responses(:delete_object, {})

      expect(client).to receive(:delete_object).with(
        hash_including(bucket: ArtifactStorage::BUCKET, key: "artifacts/abc")
      ).and_call_original

      ArtifactStorage.delete(storage_key: "artifacts/abc")
    end
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/artifact_storage_spec.rb`
Expected: FAIL — `uninitialized constant ArtifactStorage`

- [ ] **Step 4: Write ArtifactStorage**

Create `app/services/artifact_storage.rb`:

```ruby
class ArtifactStorage
  BUCKET = ENV.fetch("ARTIFACTS_S3_BUCKET", "mcpublish-artifacts-development").freeze

  def self.client
    @client ||= Aws::S3::Client.new
  end

  def self.put(storage_key:, content:)
    client.put_object(bucket: BUCKET, key: storage_key, body: content, content_type: "text/html")
  end

  def self.get(storage_key:)
    client.get_object(bucket: BUCKET, key: storage_key).body.read
  rescue Aws::S3::Errors::NoSuchKey
    nil
  end

  def self.delete(storage_key:)
    client.delete_object(bucket: BUCKET, key: storage_key)
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/artifact_storage_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 6: Commit**

```bash
git add config/initializers/aws.rb app/services/artifact_storage.rb spec/services/artifact_storage_spec.rb
git commit -m "Add ArtifactStorage S3 service"
```

---

## Task 5: MCP Protocol Scaffolding + API Key Authentication

**Files:**
- Create: `app/controllers/concerns/api_key_authentication.rb`
- Create: `app/services/mcp/tool_definitions.rb`
- Create: `app/controllers/mcp_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/mcp_protocol_spec.rb`

**Interfaces:**
- Consumes: `ApiKey.authenticate` (Task 2).
- Produces: `POST /mcp` handling `initialize` and `tools/list`; `current_api_key` helper (via `ApiKeyAuthentication` concern) that Task 6's `tools/call` handling relies on; `Mcp::ToolDefinitions::ALL`.

- [ ] **Step 1: Write the failing protocol request spec**

Create `spec/requests/mcp_protocol_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "MCP protocol", type: :request do
  let!(:api_key) { ApiKey.issue!(label: "Alice") }
  let(:token) { api_key.last }

  def post_mcp(body, token: nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: body.to_json, headers: headers
  end

  it "rejects requests with no Authorization header" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" })
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with an invalid token" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: "mcpub_bogus")
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with a revoked key's token" do
    api_key.first.update!(revoked_at: Time.current)
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "handles initialize for a valid key" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["result"]["protocolVersion"]).to be_present
    expect(body["result"]["capabilities"]).to eq({ "tools" => {} })
  end

  it "lists all four tools" do
    post_mcp({ jsonrpc: "2.0", id: 2, method: "tools/list" }, token: token)

    expect(response).to have_http_status(:ok)
    tool_names = JSON.parse(response.body)["result"]["tools"].map { |t| t["name"] }
    expect(tool_names).to contain_exactly(
      "publish_artifact", "update_artifact", "list_artifacts", "delete_artifact"
    )
  end

  it "returns a JSON-RPC error for an unknown method" do
    post_mcp({ jsonrpc: "2.0", id: 3, method: "nonexistent" }, token: token)

    body = JSON.parse(response.body)
    expect(body["error"]["code"]).to eq(-32601)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/mcp_protocol_spec.rb`
Expected: FAIL — no route matches `POST /mcp`

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `Rails.application.routes.draw do ... end` block, add:

```ruby
  post "/mcp", to: "mcp#create"
```

- [ ] **Step 4: Write the authentication concern**

Create `app/controllers/concerns/api_key_authentication.rb`:

```ruby
module ApiKeyAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
  end

  private

  def authenticate_api_key!
    @current_api_key = ApiKey.authenticate(bearer_token)
    render_unauthorized unless @current_api_key
  end

  def bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.delete_prefix("Bearer ")
  end

  def current_api_key
    @current_api_key
  end

  def render_unauthorized
    render json: {
      jsonrpc: "2.0",
      id: params[:id],
      error: { code: -32001, message: "Unauthorized: missing or invalid API key" }
    }, status: :unauthorized
  end
end
```

- [ ] **Step 5: Write the tool definitions**

Create `app/services/mcp/tool_definitions.rb`:

```ruby
module Mcp
  module ToolDefinitions
    ALL = [
      {
        name: "publish_artifact",
        description: "Publish a new self-contained HTML artifact and get back a public URL.",
        inputSchema: {
          type: "object",
          properties: {
            html: { type: "string", description: "Self-contained HTML content to publish." }
          },
          required: ["html"]
        }
      },
      {
        name: "update_artifact",
        description: "Overwrite the content of a previously published artifact, keeping its URL.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to update." },
            html: { type: "string", description: "New HTML content." }
          },
          required: %w[slug html]
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
          required: ["slug"]
        }
      }
    ].freeze
  end
end
```

- [ ] **Step 6: Write the controller**

Create `app/controllers/mcp_controller.rb`:

```ruby
class McpController < ApplicationController
  include ApiKeyAuthentication

  PROTOCOL_VERSION = "2025-06-18".freeze

  def create
    case params[:method]
    when "initialize"
      render json: success_response(initialize_result)
    when "tools/list"
      render json: success_response(tools_list_result)
    when "tools/call"
      handle_tools_call
    else
      render json: error_response(-32601, "Method not found: #{params[:method]}")
    end
  end

  private

  def initialize_result
    {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: "mcpublish", version: "0.1.0" }
    }
  end

  def tools_list_result
    { tools: Mcp::ToolDefinitions::ALL }
  end

  def handle_tools_call
    render json: error_response(-32601, "tools/call not yet implemented")
  end

  def success_response(result)
    { jsonrpc: "2.0", id: params[:id], result: result }
  end

  def error_response(code, message)
    { jsonrpc: "2.0", id: params[:id], error: { code: code, message: message } }
  end
end
```

(`handle_tools_call` is a placeholder stub here — Task 6 replaces it with the real dispatch. It's left returning a JSON-RPC error rather than raising, so the app stays in a runnable, testable state at the end of this task.)

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/mcp_protocol_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 8: Commit**

```bash
git add app/controllers/concerns/api_key_authentication.rb app/services/mcp/tool_definitions.rb app/controllers/mcp_controller.rb config/routes.rb spec/requests/mcp_protocol_spec.rb
git commit -m "Add MCP protocol scaffolding (initialize, tools/list) with API key auth"
```

---

## Task 6: MCP tools/call — Implement the Four Tools

**Files:**
- Create: `app/services/mcp/tool_dispatcher.rb`
- Create: `app/services/mcp/tools/publish_artifact.rb`
- Create: `app/services/mcp/tools/update_artifact.rb`
- Create: `app/services/mcp/tools/list_artifacts.rb`
- Create: `app/services/mcp/tools/delete_artifact.rb`
- Modify: `app/controllers/mcp_controller.rb`
- Test: `spec/requests/mcp_tools_call_spec.rb`

**Interfaces:**
- Consumes: `Artifact`, `ArtifactStorage` (Tasks 3–4); `current_api_key` (Task 5).
- Produces: `Mcp::ToolDispatcher.call(tool_name:, arguments:, api_key:)` → Hash, raises `Mcp::ToolDispatcher::ToolError`. Each `Mcp::Tools::*` class is instantiated as `.new(api_key:, arguments:).call`.

- [ ] **Step 1: Write the failing tools/call request spec**

Create `spec/requests/mcp_tools_call_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "MCP tools/call", type: :request do
  let!(:api_key_pair) { ApiKey.issue!(label: "Alice") }
  let(:api_key) { api_key_pair.first }
  let(:token) { api_key_pair.last }

  let!(:other_key_pair) { ApiKey.issue!(label: "Bob") }
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
      expect(Artifact.first.api_key).to eq(api_key)
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
      other_artifact = Artifact.create!(api_key: other_api_key, storage_key: "artifacts/x", byte_size: 5)

      not_found = call_tool("update_artifact", { slug: "nosuchslug", html: "<html></html>" })
      not_owned = call_tool("update_artifact", { slug: other_artifact.slug, html: "<html></html>" })

      expect(not_owned["result"]["content"]).to eq(not_found["result"]["content"])
    end
  end

  describe "list_artifacts" do
    it "returns only artifacts owned by the calling key" do
      call_tool("publish_artifact", { html: "<html>mine</html>" })
      Artifact.create!(api_key: other_api_key, storage_key: "artifacts/x", byte_size: 5)

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
      other_artifact = Artifact.create!(api_key: other_api_key, storage_key: "artifacts/x", byte_size: 5)

      not_found = call_tool("delete_artifact", { slug: "nosuchslug" })
      not_owned = call_tool("delete_artifact", { slug: other_artifact.slug })

      expect(not_owned["result"]["content"]).to eq(not_found["result"]["content"])
      expect(Artifact.exists?(other_artifact.id)).to eq(true)
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: FAIL — `tools/call` currently returns the Task 5 placeholder error for every case

- [ ] **Step 3: Write the tool dispatcher**

Create `app/services/mcp/tool_dispatcher.rb`:

```ruby
module Mcp
  class ToolDispatcher
    class ToolError < StandardError; end

    def self.call(tool_name:, arguments:, api_key:)
      tool_class = tool_classes[tool_name]
      raise ToolError, "Unknown tool: #{tool_name}" unless tool_class

      tool_class.new(api_key: api_key, arguments: arguments).call
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

- [ ] **Step 4: Write PublishArtifact**

Create `app/services/mcp/tools/publish_artifact.rb`:

```ruby
module Mcp
  module Tools
    class PublishArtifact
      MAX_BYTES = 5.megabytes

      def initialize(api_key:, arguments:)
        @api_key = api_key
        @html = arguments["html"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end

        artifact = Artifact.new(
          api_key: @api_key,
          storage_key: "artifacts/#{SecureRandom.uuid}",
          byte_size: @html.bytesize
        )
        artifact.save!

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::S3::Errors::ServiceError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        { content: [{ type: "text", text: artifact.url }], slug: artifact.slug, url: artifact.url }
      end
    end
  end
end
```

- [ ] **Step 5: Write UpdateArtifact**

Create `app/services/mcp/tools/update_artifact.rb`:

```ruby
module Mcp
  module Tools
    class UpdateArtifact
      MAX_BYTES = Mcp::Tools::PublishArtifact::MAX_BYTES
      NOT_FOUND_MESSAGE = "Artifact not found".freeze

      def initialize(api_key:, arguments:)
        @api_key = api_key
        @slug = arguments["slug"]
        @html = arguments["html"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: slug" if @slug.blank?
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end

        artifact = @api_key.artifacts.find_by(slug: @slug)
        raise ToolDispatcher::ToolError, NOT_FOUND_MESSAGE unless artifact

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::S3::Errors::ServiceError => e
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        artifact.update!(byte_size: @html.bytesize)

        { content: [{ type: "text", text: artifact.url }], slug: artifact.slug, url: artifact.url }
      end
    end
  end
end
```

- [ ] **Step 6: Write ListArtifacts**

Create `app/services/mcp/tools/list_artifacts.rb`:

```ruby
module Mcp
  module Tools
    class ListArtifacts
      def initialize(api_key:, arguments:)
        @api_key = api_key
      end

      def call
        artifacts = @api_key.artifacts.order(created_at: :desc).map do |artifact|
          {
            slug: artifact.slug,
            url: artifact.url,
            byte_size: artifact.byte_size,
            created_at: artifact.created_at.iso8601,
            updated_at: artifact.updated_at.iso8601
          }
        end

        { content: [{ type: "text", text: "#{artifacts.size} artifact(s)" }], artifacts: artifacts }
      end
    end
  end
end
```

- [ ] **Step 7: Write DeleteArtifact**

Create `app/services/mcp/tools/delete_artifact.rb`:

```ruby
module Mcp
  module Tools
    class DeleteArtifact
      NOT_FOUND_MESSAGE = Mcp::Tools::UpdateArtifact::NOT_FOUND_MESSAGE

      def initialize(api_key:, arguments:)
        @api_key = api_key
        @slug = arguments["slug"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: slug" if @slug.blank?

        artifact = @api_key.artifacts.find_by(slug: @slug)
        raise ToolDispatcher::ToolError, NOT_FOUND_MESSAGE unless artifact

        ArtifactStorage.delete(storage_key: artifact.storage_key)
        artifact.destroy!

        { content: [{ type: "text", text: "Deleted #{@slug}" }], success: true }
      end
    end
  end
end
```

- [ ] **Step 8: Wire tools/call into the controller**

In `app/controllers/mcp_controller.rb`, replace the `handle_tools_call` method:

```ruby
  def handle_tools_call
    tool_name = params.dig(:params, :name)
    arguments = params.dig(:params, :arguments)&.to_unsafe_h || {}

    result = Mcp::ToolDispatcher.call(tool_name: tool_name, arguments: arguments, api_key: current_api_key)
    render json: success_response(result)
  rescue Mcp::ToolDispatcher::ToolError => e
    render json: success_response({ content: [{ type: "text", text: e.message }], isError: true })
  end
```

- [ ] **Step 9: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/mcp_tools_call_spec.rb`
Expected: PASS (10 examples)

- [ ] **Step 10: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 11: Commit**

```bash
git add app/services/mcp app/controllers/mcp_controller.rb spec/requests/mcp_tools_call_spec.rb
git commit -m "Implement MCP tools/call: publish, update, list, delete artifacts"
```

---

## Task 7: Content Serving Controller

**Files:**
- Create: `app/controllers/content_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/content_spec.rb`

**Interfaces:**
- Consumes: `Artifact`, `ArtifactStorage` (Tasks 3–4).
- Produces: `GET /p/:slug` on the `content` subdomain, serving raw HTML.

- [ ] **Step 1: Write the failing content request spec**

Create `spec/requests/content_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Content serving", type: :request do
  let(:api_key) { ApiKey.issue!(label: "Alice").first }
  let(:artifact) { Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 20) }

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

  it "returns 404 for an unknown slug" do
    get "/p/nosuchslug"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the S3 object is missing despite a valid record" do
    ArtifactStorage.client.stub_responses(:get_object, "NoSuchKey")
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "is not routable on the main app host" do
    host! "mcpublish.ai"
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: FAIL — no route matches, `ContentController` undefined

- [ ] **Step 3: Add the subdomain-constrained route**

In `config/routes.rb`, add (order matters only relative to other routes with the same path, and there are none, so placement anywhere in the block is fine):

```ruby
  constraints(subdomain: "content") do
    get "/p/:slug", to: "content#show"
  end
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/content_controller.rb`:

```ruby
# Inherits ActionController::API directly (not ApplicationController) so this
# controller can never pick up session/cookie middleware, even if
# ApplicationController gains it later for the dashboard (sub-project 4).
class ContentController < ActionController::API
  def show
    artifact = Artifact.find_by(slug: params[:slug])
    return head :not_found unless artifact

    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: html, content_type: "text/html"
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/content_controller.rb config/routes.rb spec/requests/content_spec.rb
git commit -m "Serve artifact content from the content subdomain"
```

---

## Task 8: Rate Limiting

**Files:**
- Create: `config/initializers/rack_attack.rb`
- Test: `spec/requests/mcp_rate_limit_spec.rb`

**Interfaces:**
- Consumes: the `/mcp` endpoint (Tasks 5–6).
- Produces: HTTP 429 responses once a single API key exceeds 30 `publish_artifact`/`update_artifact` calls in 60 seconds.

- [ ] **Step 1: Write the failing rate limit spec**

Create `spec/requests/mcp_rate_limit_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "MCP rate limiting", type: :request do
  let(:token) { ApiKey.issue!(label: "Alice").last }

  before { Rack::Attack.cache.store.clear }

  def call_tool(name, arguments)
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  it "throttles publish_artifact calls after 30 in a minute" do
    30.times { call_tool("publish_artifact", { html: "<html>x</html>" }) }
    expect(response).not_to have_http_status(:too_many_requests)

    call_tool("publish_artifact", { html: "<html>x</html>" })
    expect(response).to have_http_status(:too_many_requests)
  end

  it "does not throttle list_artifacts even past 30 calls" do
    35.times { call_tool("list_artifacts", {}) }
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/mcp_rate_limit_spec.rb`
Expected: FAIL — the 31st `publish_artifact` call succeeds instead of being throttled

- [ ] **Step 3: Write the Rack::Attack config**

Create `config/initializers/rack_attack.rb`:

```ruby
class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  throttle("mcp/publish-updates", limit: 30, period: 60) do |request|
    next unless request.path == "/mcp" && request.post?

    body = request.body.read
    request.body.rewind

    payload = begin
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
    next unless payload
    next unless payload["method"] == "tools/call"
    next unless %w[publish_artifact update_artifact].include?(payload.dig("params", "name"))

    request.get_header("HTTP_AUTHORIZATION")
  end
end

Rails.application.config.middleware.use Rack::Attack
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/mcp_rate_limit_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 5: Run the full suite to check for regressions**

Run: `bundle exec rspec`
Expected: PASS, all examples

- [ ] **Step 6: Commit**

```bash
git add config/initializers/rack_attack.rb spec/requests/mcp_rate_limit_spec.rb
git commit -m "Rate limit publish/update calls to 30 per minute per API key"
```
