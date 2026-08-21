module Mcp
  module Tools
    module OrganizationResolver
      module_function

      def resolve(user:, slug:)
        organization = user.organizations.find_by(slug: slug)
        raise ToolDispatcher::ToolError, "Organization not found: #{slug}" unless organization

        organization
      end
    end
  end
end
