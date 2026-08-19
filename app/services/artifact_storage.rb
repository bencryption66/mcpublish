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
