module Mcp
  class ToolDispatcher
    class ToolError < StandardError; end

    def self.call(tool_name:, arguments:, user:)
      tool_class = tool_classes[tool_name]
      raise ToolError, "Unknown tool: #{tool_name}" unless tool_class

      tool_class.new(user: user, arguments: arguments).call
    end

    def self.tool_classes
      {
        "publish_artifact" => Mcp::Tools::PublishArtifact,
        "update_artifact" => Mcp::Tools::UpdateArtifact,
        "list_artifacts" => Mcp::Tools::ListArtifacts,
        "delete_artifact" => Mcp::Tools::DeleteArtifact
      }
    end
  end
end
