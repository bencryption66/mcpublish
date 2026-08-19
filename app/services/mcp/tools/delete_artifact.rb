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
