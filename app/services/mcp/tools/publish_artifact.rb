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
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        { content: [{ type: "text", text: artifact.url }], slug: artifact.slug, url: artifact.url }
      end
    end
  end
end
