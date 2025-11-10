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
    module FieldOperations
      # Adds a new field to a table.
      #
      # @param table_id [String] Table identifier
      # @param field_data [Hash] Field configuration (slug, label, field_type, params)
      # @param field_position [Hash, nil] Optional positioning metadata
      # @param auto_fill_structure_layout [Boolean] Auto-update layout (default: true)
      # @return [Hash] Created field object (may be empty on success)
      def add_field(table_id, field_data, field_position: nil, auto_fill_structure_layout: true)
        log_metric("→ Adding field to table: #{table_id}")

        body = {
          'field' => field_data,
          'field_position' => field_position || {},
          'auto_fill_structure_layout' => auto_fill_structure_layout
        }

        response = api_request(:post, "/applications/#{table_id}/add_field/", body)

        if response.is_a?(Hash)
          log_metric("✓ Field added successfully: #{field_data['label']}")
        end

        response
      end

      # Adds multiple fields to a table in one request.
      #
      # More efficient than multiple add_field calls. Note: Some field types
      # (Formula, Count, TimeTracking) not supported in bulk operations.
      #
      # @param table_id [String] Table identifier
      # @param fields [Array<Hash>] Array of field configurations
      # @param set_as_visible_fields_in_reports [Array<String>, nil] Optional view IDs to make fields visible
      # @return [Hash] Bulk operation result
      def bulk_add_fields(table_id, fields, set_as_visible_fields_in_reports: nil)
        log_metric("→ Bulk adding #{fields.size} fields to table: #{table_id}")

        body = {
          'fields' => fields
        }

        body['set_as_visible_fields_in_reports'] = set_as_visible_fields_in_reports if set_as_visible_fields_in_reports

        response = api_request(:post, "/applications/#{table_id}/bulk-add-fields/", body)

        log_metric("✓ Successfully added #{fields.size} fields")

        response
      end

      # Updates an existing field's configuration.
      #
      # Uses PUT method. The slug identifies the field to update.
      #
      # @param table_id [String] Table identifier
      # @param slug [String] Field slug to update
      # @param field_data [Hash] Updated field configuration
      # @return [Hash] Updated field object
      def update_field(table_id, slug, field_data)
        log_metric("→ Updating field #{slug} in table: #{table_id}")

        # Ensure slug is included in the field data
        body = field_data.merge('slug' => slug)

        response = api_request(:put, "/applications/#{table_id}/change_field/", body)

        if response.is_a?(Hash)
          log_metric("✓ Field updated successfully: #{slug}")
        end

        response
      end

      # Deletes a field from a table.
      #
      # PERMANENT OPERATION - cannot be undone. Removes the field and all its data.
      #
      # @param table_id [String] Table identifier
      # @param slug [String] Field slug to delete
      # @return [Hash] Deleted field object
      def delete_field(table_id, slug)
        log_metric("→ Deleting field #{slug} from table: #{table_id}")

        body = {
          'slug' => slug
        }

        response = api_request(:post, "/applications/#{table_id}/delete_field/", body)

        if response.is_a?(Hash)
          log_metric("✓ Field deleted successfully: #{slug}")
        end

        response
      end
    end
  end
end
