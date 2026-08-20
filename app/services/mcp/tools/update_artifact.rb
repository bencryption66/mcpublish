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
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        artifact.update!(byte_size: @html.bytesize)

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end
    end
  end
end
