# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/smart_suite_client"

class TestViewOperations < Minitest::Test
  def setup
    @api_key = "test_api_key"
    @account_id = "test_account_id"
    @client = SmartSuiteClient.new(@api_key, @account_id)
  end

  # ========== get_view_records tests ==========

  def test_get_view_records_success
    table_id = "tbl_123"
    view_id = "view_456"

    expected_response = {
      "records" => [
        { "id" => "rec_1", "title" => "Record 1", "status" => "Active" },
        { "id" => "rec_2", "title" => "Record 2", "status" => "Pending" }
      ],
      "total" => 2
    }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, _body = nil|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      expected_response
    end

    result = @client.get_view_records(table_id, view_id, format: :json)

    assert_equal :get, captured_args[:method]
    assert_includes captured_args[:endpoint], "/applications/tbl_123/records-for-report/"
    assert_includes captured_args[:endpoint], "report=view_456"
    assert_equal 2, result["records"].length
    assert_equal "rec_1", result["records"][0]["id"]
    assert_equal "rec_2", result["records"][1]["id"]
  end

  def test_get_view_records_with_empty_values
    table_id = "tbl_123"
    view_id = "view_456"

    captured_endpoint = nil
    @client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      captured_endpoint = endpoint
      { "records" => [] }
    end

    @client.get_view_records(table_id, view_id, with_empty_values: true)

    assert_includes captured_endpoint, "with_empty_values=true"
  end

  def test_get_view_records_without_empty_values
    table_id = "tbl_123"
    view_id = "view_456"

    captured_endpoint = nil
    @client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      captured_endpoint = endpoint
      { "records" => [] }
    end

    @client.get_view_records(table_id, view_id)

    # with_empty_values should not be in the endpoint when false/default
    refute_includes captured_endpoint, "with_empty_values"
  end

  def test_get_view_records_empty_result
    table_id = "tbl_123"
    view_id = "view_456"

    expected_response = { "records" => [], "total" => 0 }

    @client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      expected_response
    end

    result = @client.get_view_records(table_id, view_id, format: :json)

    assert_equal 0, result["records"].length
  end

  def test_get_view_records_missing_table_id
    assert_raises(ArgumentError) do
      @client.get_view_records(nil, "view_456")
    end

    assert_raises(ArgumentError) do
      @client.get_view_records("", "view_456")
    end
  end

  def test_get_view_records_missing_view_id
    assert_raises(ArgumentError) do
      @client.get_view_records("tbl_123", nil)
    end

    assert_raises(ArgumentError) do
      @client.get_view_records("tbl_123", "")
    end
  end

  # ========== create_view tests ==========

  def test_create_view_basic_success
    application = "tbl_123"
    solution = "sol_456"
    label = "My Grid View"
    view_mode = "grid"

    expected_response = {
      "id" => "view_new",
      "application" => application,
      "solution" => solution,
      "label" => label,
      "view_mode" => view_mode
    }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, body|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      captured_args[:body] = body
      expected_response
    end

    result = @client.create_view(application, solution, label, view_mode, format: :json)

    assert_equal :post, captured_args[:method]
    assert_equal "/reports/", captured_args[:endpoint]
    assert_equal application, captured_args[:body]["application"]
    assert_equal solution, captured_args[:body]["solution"]
    assert_equal label, captured_args[:body]["label"]
    assert_equal view_mode, captured_args[:body]["view_mode"]
    # Check defaults
    assert_equal true, captured_args[:body]["autosave"]
    assert_equal false, captured_args[:body]["is_locked"]
    assert_equal false, captured_args[:body]["is_private"]
    assert_equal false, captured_args[:body]["is_password_protected"]
    assert_equal "view_new", result["id"]
    assert_equal "My Grid View", result["label"]
  end

  def test_create_view_with_all_options
    application = "tbl_123"
    solution = "sol_456"
    label = "Full Options View"
    view_mode = "kanban"

    options = {
      description: "A view with all options",
      autosave: false,
      is_locked: true,
      is_private: true,
      is_password_protected: true,
      order: 5,
      state: { "filter" => { "operator" => "and", "fields" => [] } },
      map_state: { "center" => [ 0, 0 ] },
      sharing: { "enabled" => true }
    }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      { "id" => "view_full", "label" => label }
    end

    result = @client.create_view(application, solution, label, view_mode, format: :json, **options)

    assert_equal "A view with all options", captured_body["description"]
    assert_equal false, captured_body["autosave"]
    assert_equal true, captured_body["is_locked"]
    assert_equal true, captured_body["is_private"]
    assert_equal true, captured_body["is_password_protected"]
    assert_equal 5, captured_body["order"]
    assert_equal({ "operator" => "and", "fields" => [] }, captured_body["state"]["filter"])
    assert_equal [ 0, 0 ], captured_body["map_state"]["center"]
    assert_equal({ "enabled" => true }, captured_body["sharing"])
    assert_equal "view_full", result["id"]
  end

  def test_create_view_different_modes
    view_modes = %w[grid map calendar kanban gallery timeline gantt]

    view_modes.each do |mode|
      captured_body = nil
      @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
        captured_body = body
        { "id" => "view_id", "view_mode" => mode, "label" => "Test" }
      end

      result = @client.create_view("tbl_123", "sol_456", "Test", mode, format: :json)

      assert_equal mode, captured_body["view_mode"]
      assert_equal mode, result["view_mode"]
    end
  end

  def test_create_view_missing_application
    assert_raises(ArgumentError) do
      @client.create_view(nil, "sol_456", "Label", "grid")
    end

    assert_raises(ArgumentError) do
      @client.create_view("", "sol_456", "Label", "grid")
    end
  end

  def test_create_view_missing_solution
    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", nil, "Label", "grid")
    end

    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", "", "Label", "grid")
    end
  end

  def test_create_view_missing_label
    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", "sol_456", nil, "grid")
    end

    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", "sol_456", "", "grid")
    end
  end

  def test_create_view_missing_view_mode
    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", "sol_456", "Label", nil)
    end

    assert_raises(ArgumentError) do
      @client.create_view("tbl_123", "sol_456", "Label", "")
    end
  end

  def test_create_view_optional_fields_not_included_when_nil
    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      { "id" => "view_id", "label" => "Test" }
    end

    @client.create_view("tbl_123", "sol_456", "Test", "grid")

    refute captured_body.key?("description")
    refute captured_body.key?("order")
    refute captured_body.key?("state")
    refute captured_body.key?("map_state")
    refute captured_body.key?("sharing")
  end

  def test_create_view_partial_options
    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      { "id" => "view_id", "label" => "Test" }
    end

    @client.create_view("tbl_123", "sol_456", "Test", "grid",
                        description: "My description", order: 3)

    # Only provided options should be included
    assert_equal "My description", captured_body["description"]
    assert_equal 3, captured_body["order"]
    refute captured_body.key?("state")
    refute captured_body.key?("map_state")
  end
end
