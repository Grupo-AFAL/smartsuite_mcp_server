# frozen_string_literal: true

require_relative 'base'

module SmartSuite
  module API
    # FieldOperations handles table schema management (field CRUD).
    #
    # This module provides methods for:
    # - Adding single or multiple fields to tables
    # - Updating existing field definitions
    # - Deleting fields from tables
    #
    # All operations are permanent and modify the table structure.
    # Uses Base module for common API patterns (validation, endpoint building).
    module FieldOperations
      include Base

      # Adds a new field to a table.
      #
      # @param table_id [String] Table identifier
      # @param field_data [Hash] Field configuration (slug, label, field_type, params)
      # @param field_position [Hash, nil] Optional positioning metadata
      # @param auto_fill_structure_layout [Boolean] Auto-update layout (default: true)
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Created field object in requested format
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   add_field("tbl_123", {
      #     "slug" => "abc123",
      #     "label" => "Priority",
      #     "field_type" => "singleselectfield",
      #     "params" => {"choices" => ["High", "Medium", "Low"]}
      #   })
      def add_field(table_id, field_data, field_position: nil, auto_fill_structure_layout: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('field_data', field_data, Hash)

        log_metric("→ Adding field to table: #{table_id}")

        body = {
          'field' => field_data,
          'field_position' => field_position || {},
          'auto_fill_structure_layout' => auto_fill_structure_layout
        }

        response = api_request(:post, "/applications/#{table_id}/add_field/", body)

        if response.is_a?(Hash)
          # Invalidate cache since table structure changed
          @cache&.invalidate_table_cache(table_id, structure_changed: true)
          format_single_response(response, format)
        else
          response
        end
      end

      # Adds multiple fields to a table in one request.
      #
      # More efficient than multiple add_field calls. Note: Some field types
      # (Formula, Count, TimeTracking) not supported in bulk operations.
      #
      # @param table_id [String] Table identifier
      # @param fields [Array<Hash>] Array of field configurations
      # @param set_as_visible_fields_in_reports [Array<String>, nil] Optional view IDs to make fields visible
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Bulk operation result in requested format
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   bulk_add_fields("tbl_123", [
      #     {"slug" => "field1", "label" => "Status", "field_type" => "statusfield"},
      #     {"slug" => "field2", "label" => "Priority", "field_type" => "singleselectfield"}
      #   ])
      def bulk_add_fields(table_id, fields, set_as_visible_fields_in_reports: nil, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('fields', fields, Array)

        log_metric("→ Bulk adding #{fields.size} fields to table: #{table_id}")

        body = {
          'fields' => fields
        }

        body['set_as_visible_fields_in_reports'] = set_as_visible_fields_in_reports if set_as_visible_fields_in_reports

        response = api_request(:post, "/applications/#{table_id}/bulk-add-fields/", body)

        # Invalidate cache since table structure changed
        @cache&.invalidate_table_cache(table_id, structure_changed: true)

        format_single_response(response, format)
      end

      # Updates an existing field's configuration.
      #
      # Uses PUT method. The slug identifies the field to update.
      #
      # @param table_id [String] Table identifier
      # @param slug [String] Field slug to update
      # @param field_data [Hash] Updated field configuration
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Updated field object in requested format
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   update_field("tbl_123", "abc123", {
      #     "label" => "Updated Priority",
      #     "field_type" => "singleselectfield",
      #     "params" => {"choices" => ["Urgent", "High", "Medium", "Low"]}
      #   })
      def update_field(table_id, slug, field_data, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('slug', slug)
        validate_required_parameter!('field_data', field_data, Hash)

        log_metric("→ Updating field #{slug} in table: #{table_id}")

        # Ensure slug is included in the field data
        # params is required by SmartSuite API, default to empty hash if not provided
        body = field_data.merge('slug' => slug)
        body['params'] ||= {}

        response = api_request(:put, "/applications/#{table_id}/change_field/", body)

        if response.is_a?(Hash)
          # Invalidate cache since table structure changed
          @cache&.invalidate_table_cache(table_id, structure_changed: true)
          format_single_response(response, format)
        else
          response
        end
      end

      # Deletes a field from a table.
      #
      # PERMANENT OPERATION - cannot be undone. Removes the field and all its data.
      #
      # @param table_id [String] Table identifier
      # @param slug [String] Field slug to delete
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Deleted field object in requested format
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   delete_field("tbl_123", "abc123")
      def delete_field(table_id, slug, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('slug', slug)

        log_metric("→ Deleting field #{slug} from table: #{table_id}")

        body = {
          'slug' => slug
        }

        response = api_request(:post, "/applications/#{table_id}/delete_field/", body)

        if response.is_a?(Hash)
          # Invalidate cache since table structure changed
          @cache&.invalidate_table_cache(table_id, structure_changed: true)
          format_single_response(response, format)
        else
          response
        end
      end
    end
  end
end
