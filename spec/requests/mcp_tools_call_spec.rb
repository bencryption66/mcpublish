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
end
