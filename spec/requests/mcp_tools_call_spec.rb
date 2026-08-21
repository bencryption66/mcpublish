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

    it "does not partially apply shared_with when a later email is malformed" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "shared", shared_with: [ "good@example.com", "not-an-email" ] })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
      expect(ArtifactShare.count).to eq(0)
    end

    it "rejects an invalid visibility value" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", visibility: "bogus" })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "rejects an organization param when visibility is not organisation" do
      Organization.create!(name: "Acme", slug: "acme")

      result = call_tool("publish_artifact", { html: "<html>hi</html>", organization: "acme" })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.count).to eq(0)
    end

    it "rejects a shared_with param when visibility is not shared" do
      result = call_tool("publish_artifact", { html: "<html>hi</html>", shared_with: [ "x@example.com" ] })

      expect(result["result"]["isError"]).to eq(true)
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
      other_artifact = Artifact.create!(user: other_user, storage_key: "artifacts/x", byte_size: 5)

      not_found = call_tool("update_artifact", { slug: "nosuchslug", html: "<html></html>" })
      not_owned = call_tool("update_artifact", { slug: other_artifact.slug, html: "<html></html>" })

      expect(not_owned["result"]["content"]).to eq(not_found["result"]["content"])
    end

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

    it "does not partially apply shared_with when a later email is malformed, leaving the prior list intact" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "shared", shared_with: [ "a@example.com" ] })
      slug = publish_result["result"]["slug"]

      result = call_tool("update_artifact", { slug: slug, shared_with: [ "good@example.com", "not-an-email" ] })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.find_by(slug: slug).artifact_shares.pluck(:email)).to eq([ "a@example.com" ])
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

    it "changes organization without resending visibility" do
      org = Organization.create!(name: "Acme", slug: "acme")
      OrganizationMembership.create!(user: user, organization: org, role: "admin")
      other_org = Organization.create!(name: "Globex", slug: "globex")
      OrganizationMembership.create!(user: user, organization: other_org, role: "admin")
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "organisation", organization: "acme" })
      slug = publish_result["result"]["slug"]

      result = call_tool("update_artifact", { slug: slug, organization: "globex" })

      expect(result["result"]["isError"]).to be_nil
      expect(Artifact.find_by(slug: slug).organization.slug).to eq("globex")
    end

    it "does not re-check organization membership on an unrelated html-only update" do
      org = Organization.create!(name: "Acme", slug: "acme")
      membership = OrganizationMembership.create!(user: user, organization: org, role: "admin")
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>", visibility: "organisation", organization: "acme" })
      slug = publish_result["result"]["slug"]

      membership.destroy!

      result = call_tool("update_artifact", { slug: slug, html: "<html>v2</html>" })

      expect(result["result"]["isError"]).to be_nil
      expect(Artifact.find_by(slug: slug).byte_size).to eq("<html>v2</html>".bytesize)
    end

    it "rejects an organization param when the effective visibility is not organisation" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>" })
      slug = publish_result["result"]["slug"]
      Organization.create!(name: "Acme", slug: "acme")

      result = call_tool("update_artifact", { slug: slug, organization: "acme" })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.find_by(slug: slug).organization).to be_nil
    end

    it "rejects a shared_with param when the effective visibility is not shared" do
      publish_result = call_tool("publish_artifact", { html: "<html>v1</html>" })
      slug = publish_result["result"]["slug"]

      result = call_tool("update_artifact", { slug: slug, shared_with: [ "x@example.com" ] })

      expect(result["result"]["isError"]).to eq(true)
      expect(Artifact.find_by(slug: slug).artifact_shares).to be_empty
    end
  end

  describe "list_artifacts" do
    it "returns only artifacts owned by the calling user" do
      call_tool("publish_artifact", { html: "<html>mine</html>" })
      Artifact.create!(user: other_user, storage_key: "artifacts/x", byte_size: 5)

      result = call_tool("list_artifacts", {})

      expect(result["result"]["artifacts"].length).to eq(1)
    end

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
