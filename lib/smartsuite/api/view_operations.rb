# frozen_string_literal: true

require_relative 'base'

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
      # @return [Hash] Records array with view configuration
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   get_view_records("tbl_123", "view_456")
      #   get_view_records("tbl_123", "view_456", with_empty_values: true)
      def get_view_records(table_id, view_id, with_empty_values: false)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('view_id', view_id)

        log_metric("→ Getting records for view: #{view_id} in table: #{table_id}")

        # Build endpoint with query parameters using Base helper
        base_path = "/applications/#{table_id}/records-for-report/"
        endpoint = build_endpoint(base_path, report: view_id, with_empty_values: with_empty_values || nil)

        response = api_request(:get, endpoint)

        if response.is_a?(Hash)
          record_count = response['records']&.size || 0
          log_metric("✓ Retrieved #{record_count} records for view")
        end

        response
      end

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
      # @return [Hash] Created view details
      # @raise [ArgumentError] If required parameters are missing
      # @example Basic grid view
      #   create_view("tbl_123", "sol_456", "My View", "grid")
      #
      # @example Map view with state
      #   create_view("tbl_123", "sol_456", "Location Map", "map",
      #               state: {filter: {...}}, map_state: {center: [...]})
      def create_view(application, solution, label, view_mode, **options)
        validate_required_parameter!('application', application)
        validate_required_parameter!('solution', solution)
        validate_required_parameter!('label', label)
        validate_required_parameter!('view_mode', view_mode)

        log_metric("→ Creating view: #{label} in application: #{application}")

        body = {
          'application' => application,
          'solution' => solution,
          'label' => label,
          'view_mode' => view_mode,
          'autosave' => options.fetch(:autosave, true),
          'is_locked' => options.fetch(:is_locked, false),
          'is_private' => options.fetch(:is_private, false),
          'is_password_protected' => options.fetch(:is_password_protected, false)
        }

        # Add optional fields
        body['description'] = options[:description] if options[:description]
        body['order'] = options[:order] if options[:order]
        body['state'] = options[:state] if options[:state]
        body['map_state'] = options[:map_state] if options[:map_state]
        body['sharing'] = options[:sharing] if options[:sharing]

        response = api_request(:post, '/reports/', body)

        log_metric("✓ Created view: #{response['label']} (#{response['id']})") if response.is_a?(Hash)

        response
      end
    end
  end
end
