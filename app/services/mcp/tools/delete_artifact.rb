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
