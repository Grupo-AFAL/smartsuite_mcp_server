# frozen_string_literal: true

require_relative "base"
require_relative "../formatters/toon_formatter"

module SmartSuite
  module API
    # ViewOperations handles API calls for view (report) management.
    #
    # This module provides methods for:
    # - Creating views (reports)
    # - Getting records for a specific view with applied filters
    #
    # Note: In SmartSuite's API, views are also referred to as "reports"
    # Uses Base module for common API patterns (validation, endpoint building).
    module ViewOperations
      include Base

      # Gets records for a specified view with the view's filters applied.
      #
      # This method retrieves records that match the view's configured filters,
      # sorting, and field visibility settings.
      #
      # @param table_id [String] Table identifier
      # @param view_id [String] View (report) identifier
      # @param with_empty_values [Boolean] Whether to include empty field values (default: false)
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Hash] TOON string or JSON hash depending on format
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   get_view_records("tbl_123", "view_456")
      #   get_view_records("tbl_123", "view_456", format: :json)
      def get_view_records(table_id, view_id, with_empty_values: false, format: :toon)
        validate_required_parameter!("table_id", table_id)
        validate_required_parameter!("view_id", view_id)

        # Build endpoint with query parameters using Base helper
        base_path = "/applications/#{table_id}/records-for-report/"
        endpoint = build_endpoint(base_path, report: view_id, with_empty_values: with_empty_values || nil)

        response = api_request(:get, endpoint)

        return response unless response.is_a?(Hash) && response["records"].is_a?(Array)

        format_view_records_output(response, format)
      end

      # Lists all views (reports) for the account, optionally filtered by table or solution.
      #
      # Returns views with their configuration including filters, sorting, grouping,
      # and display settings.
      #
      # @param table_id [String, nil] Optional table ID to filter views
      # @param solution_id [String, nil] Optional solution ID to filter views
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Array] TOON string or JSON array depending on format
      # @example List all views
      #   list_views
      #
      # @example List views for a specific table
      #   list_views(table_id: "tbl_123")
      #
      # @example List views for a solution
      #   list_views(solution_id: "sol_456")
      def list_views(table_id: nil, solution_id: nil, format: :toon)
        # Try cache first if enabled
        cached_views = with_cache_check("views", "table:#{table_id}|solution:#{solution_id}") do
          @cache.get_cached_views(table_id: table_id, solution_id: solution_id)
        end

        if cached_views
          return format_views_output(cached_views, format)
        end

        # Fetch from API
        response = api_request(:get, "/reports/")
        return response unless response.is_a?(Array)

        # Cache the full response (before filtering)
        cache_views_response(response) if cache_enabled?

        # Filter by table or solution if specified
        views = filter_views(response, table_id: table_id, solution_id: solution_id)

        # Extract essential fields for each view
        simplified_views = simplify_views(views)

        format_views_output(simplified_views, format)
      end

      private

      # Filter views by table_id or solution_id
      #
      # @param views [Array<Hash>] All views
      # @param table_id [String, nil] Optional table ID filter
      # @param solution_id [String, nil] Optional solution ID filter
      # @return [Array<Hash>] Filtered views
      def filter_views(views, table_id: nil, solution_id: nil)
        if table_id
          views.select { |v| v["application"] == table_id }
        elsif solution_id
          views.select { |v| v["solution"] == solution_id }
        else
          views
        end
      end

      # Extract essential fields from views
      #
      # @param views [Array<Hash>] Views with full data
      # @return [Array<Hash>] Simplified views
      def simplify_views(views)
        views.map do |view|
          {
            "id" => view["id"],
            "label" => view["label"],
            "description" => view["description"],
            "view_mode" => view["view_mode"],
            "solution" => view["solution"],
            "application" => view["application"],
            "is_locked" => view["is_locked"],
            "is_private" => view["is_private"],
            "order" => view["order"]
          }
        end
      end

      # Format views output based on format parameter
      #
      # @param views [Array<Hash>] Views to format
      # @param format [Symbol] Output format (:toon or :json)
      # @return [String, Array] Formatted output
      def format_views_output(views, format)
        case format
        when :toon
          SmartSuite::Formatters::ToonFormatter.format({ "views" => views })
        else
          views
        end
      end

      # Cache views response
      #
      # @param views [Array<Hash>] Views from API
      def cache_views_response(views)
        @cache.cache_views(views)
      rescue StandardError => e
        SmartSuite::Logger.error("Failed to cache views", error: e)
      end

      # Format view records output based on format parameter
      #
      # @param response [Hash] API response with records array
      # @param format [Symbol] Output format (:toon or :json)
      # @return [String, Hash] Formatted output
      def format_view_records_output(response, format)
        records = response["records"]
        record_count = records.size

        case format
        when :toon
          SmartSuite::Formatters::ToonFormatter.format_records(records, total_count: record_count)
        else # :json
          response
        end
      end

      public

      # Creates a new view (report) in a table.
      #
      # Creates a view with specified configuration including view type,
      # filters, sorting, grouping, and display settings.
      #
      # @param application [String] Table identifier where view is created
      # @param solution [String] Solution identifier containing the table
      # @param label [String] Display name of the view
      # @param view_mode [String] View type: grid, map, calendar, kanban, gallery, timeline, gantt
      # @param options [Hash] Optional view configuration
      # @option options [String] :description View description
      # @option options [Boolean] :autosave Enable autosave (default: true)
      # @option options [Boolean] :is_locked Lock the view (default: false)
      # @option options [Boolean] :is_private Make view private (default: false)
      # @option options [Boolean] :is_password_protected Password protect view (default: false)
      # @option options [Integer] :order Display position in view list
      # @option options [Hash] :state View state (filter, fields, sort, group settings)
      # @option options [Hash] :map_state Map configuration for map views
      # @option options [Hash] :sharing Sharing settings
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Created view details in requested format
      # @raise [ArgumentError] If required parameters are missing
      # @example Basic grid view
      #   create_view("tbl_123", "sol_456", "My View", "grid")
      #
      # @example Map view with state
      #   create_view("tbl_123", "sol_456", "Location Map", "map",
      #               state: {filter: {...}}, map_state: {center: [...]})
      def create_view(application, solution, label, view_mode, format: :toon, **options)
        validate_required_parameter!("application", application)
        validate_required_parameter!("solution", solution)
        validate_required_parameter!("label", label)
        validate_required_parameter!("view_mode", view_mode)

        body = {
          "application" => application,
          "solution" => solution,
          "label" => label,
          "view_mode" => view_mode,
          "autosave" => options[:autosave].nil? ? true : options[:autosave],
          "is_locked" => options[:is_locked].nil? ? false : options[:is_locked],
          "is_private" => options[:is_private].nil? ? false : options[:is_private],
          "is_password_protected" => options[:is_password_protected].nil? ? false : options[:is_password_protected]
        }

        # Add optional fields
        body["description"] = options[:description] if options[:description]
        body["order"] = options[:order] if options[:order]
        body["state"] = options[:state] if options[:state]
        body["map_state"] = options[:map_state] if options[:map_state]
        body["sharing"] = options[:sharing] if options[:sharing]

        response = api_request(:post, "/reports/", body)

        return response unless response.is_a?(Hash)

        format_single_response(response, format)
      end
    end
  end
end
