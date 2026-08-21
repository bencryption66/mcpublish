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
