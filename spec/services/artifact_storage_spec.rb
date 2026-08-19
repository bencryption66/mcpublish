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
