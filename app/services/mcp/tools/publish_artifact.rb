module Mcp
  module Tools
    class PublishArtifact
      MAX_BYTES = 5.megabytes
      MAX_SLUG_ATTEMPTS = 3

      def initialize(user:, arguments:)
        @user = user
        @html = arguments["html"]
        @visibility = arguments["visibility"] || "private"
        @organization_slug = arguments["organization"]
        @shared_with = arguments["shared_with"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end
        unless Artifact::VISIBILITIES.include?(@visibility)
          raise ToolDispatcher::ToolError, "Invalid visibility: #{@visibility}"
        end

        organization = @visibility == "organisation" ? OrganizationResolver.resolve(user: @user, slug: @organization_slug) : nil

        artifact = create_artifact_with_retry(organization)

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        if @visibility == "shared" && @shared_with.present?
          begin
            SharedWithApplier.apply(artifact: artifact, emails: @shared_with)
          rescue ToolDispatcher::ToolError
            artifact.destroy!
            raise
          end
        end

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end

      private

      # SlugGenerator checks Artifact.exists? before the caller inserts, so two
      # concurrent publishes can both pass that check for the same slug before
      # either commits — the DB's unique index then rejects the loser. Retry
      # with a freshly-generated slug rather than surfacing a raw DB error.
      def create_artifact_with_retry(organization)
        attempts = 0
        begin
          attempts += 1
          artifact = Artifact.new(
            user: @user,
            storage_key: "artifacts/#{SecureRandom.uuid}",
            byte_size: @html.bytesize,
            visibility: @visibility,
            organization: organization
          )
          artifact.save!
          artifact
        rescue ActiveRecord::RecordNotUnique
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.errors.of_kind?(:slug, :taken)
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        end
      end
    end
  end
end
