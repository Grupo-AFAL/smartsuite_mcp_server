# frozen_string_literal: true

module SmartSuite
  module MCP
    # ResourceRegistry manages MCP resources (currently empty).
    #
    # This module handles the resources/list MCP method. Resources represent
    # stateful data that the MCP server can provide. Currently not implemented
    # for SmartSuite integration.
    module ResourceRegistry
      # Generates a JSON-RPC 2.0 response for the resources/list MCP method.
      #
      # @param request [Hash] The MCP request containing the request ID
      # @return [Hash] JSON-RPC 2.0 response with empty resources array
      def self.resources_list(request)
        {
          'jsonrpc' => '2.0',
          'id' => request['id'],
          'result' => {
            'resources' => []
          }
        }
      end
    end
  end
end
