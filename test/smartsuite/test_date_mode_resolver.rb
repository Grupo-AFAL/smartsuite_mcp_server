# frozen_string_literal: true

require "minitest/autorun"
require "date"
require_relative "../../lib/smart_suite/date_mode_resolver"

# Tests for SmartSuite::DateModeResolver
#
# This module resolves SmartSuite date_mode values (like "today", "yesterday")
# to actual date strings. It was extracted to fix SMARTSUITE-MCP-9 where
# a filter with { "date_mode" => "today" } caused NoMethodError because
# the code tried to call .to_f on a Hash.
class TestDateModeResolver < Minitest::Test
  # ============================================
  # Tests for .resolve
  # ============================================

  def test_resolve_today
    assert_equal Date.today.to_s, SmartSuite::DateModeResolver.resolve("today")
  end

  def test_resolve_yesterday
    assert_equal (Date.today - 1).to_s, SmartSuite::DateModeResolver.resolve("yesterday")
  end

  def test_resolve_tomorrow
    assert_equal (Date.today + 1).to_s, SmartSuite::DateModeResolver.resolve("tomorrow")
  end

  def test_resolve_one_week_ago
    assert_equal (Date.today - 7).to_s, SmartSuite::DateModeResolver.resolve("one_week_ago")
  end

  def test_resolve_one_week_from_now
    assert_equal (Date.today + 7).to_s, SmartSuite::DateModeResolver.resolve("one_week_from_now")
  end

  def test_resolve_one_month_ago
    expected = (Date.today << 1).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("one_month_ago")
  end

  def test_resolve_one_month_from_now
    expected = (Date.today >> 1).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("one_month_from_now")
  end

  def test_resolve_start_of_week
    today = Date.today
    expected = (today - today.wday).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("start_of_week")
  end

  def test_resolve_end_of_week
    today = Date.today
    expected = (today + (6 - today.wday)).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("end_of_week")
  end

  def test_resolve_start_of_month
    today = Date.today
    expected = Date.new(today.year, today.month, 1).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("start_of_month")
  end

  def test_resolve_end_of_month
    today = Date.today
    expected = Date.new(today.year, today.month, -1).to_s
    assert_equal expected, SmartSuite::DateModeResolver.resolve("end_of_month")
  end

  def test_resolve_nil_returns_nil
    assert_nil SmartSuite::DateModeResolver.resolve(nil)
  end

  def test_resolve_unknown_mode_returns_as_string
    assert_equal "custom_value", SmartSuite::DateModeResolver.resolve("custom_value")
  end

  def test_resolve_is_case_insensitive
    assert_equal Date.today.to_s, SmartSuite::DateModeResolver.resolve("TODAY")
    assert_equal Date.today.to_s, SmartSuite::DateModeResolver.resolve("Today")
    assert_equal Date.today.to_s, SmartSuite::DateModeResolver.resolve("tOdAy")
  end

  # ============================================
  # Tests for .extract_date_value
  # ============================================

  def test_extract_date_value_with_date_mode_today
    # This was the exact filter that caused SMARTSUITE-MCP-9
    value = { "date_mode" => "today" }
    result = SmartSuite::DateModeResolver.extract_date_value(value)

    assert_equal Date.today.to_s, result
    refute result.is_a?(Hash), "Result should be a string, not a Hash"
  end

  def test_extract_date_value_prefers_date_mode_value
    value = {
      "date_mode" => "today",
      "date_mode_value" => "2025-01-15"
    }
    assert_equal "2025-01-15", SmartSuite::DateModeResolver.extract_date_value(value)
  end

  def test_extract_date_value_uses_date_key_as_second_priority
    value = {
      "date_mode" => "today",
      "date" => "2025-02-20"
    }
    assert_equal "2025-02-20", SmartSuite::DateModeResolver.extract_date_value(value)
  end

  def test_extract_date_value_with_only_date_key
    value = { "date" => "2025-06-20" }
    assert_equal "2025-06-20", SmartSuite::DateModeResolver.extract_date_value(value)
  end

  def test_extract_date_value_with_plain_string
    assert_equal "2025-03-10", SmartSuite::DateModeResolver.extract_date_value("2025-03-10")
  end

  def test_extract_date_value_with_empty_hash
    assert_nil SmartSuite::DateModeResolver.extract_date_value({})
  end

  def test_extract_date_value_priority_order
    # All three present: date_mode_value wins
    value = {
      "date_mode" => "today",
      "date_mode_value" => "2025-01-01",
      "date" => "2025-02-02"
    }
    assert_equal "2025-01-01", SmartSuite::DateModeResolver.extract_date_value(value)

    # date_mode_value and date: date_mode_value wins
    value = {
      "date_mode_value" => "2025-01-01",
      "date" => "2025-02-02"
    }
    assert_equal "2025-01-01", SmartSuite::DateModeResolver.extract_date_value(value)

    # date and date_mode: date wins
    value = {
      "date_mode" => "today",
      "date" => "2025-02-02"
    }
    assert_equal "2025-02-02", SmartSuite::DateModeResolver.extract_date_value(value)

    # Only date_mode: resolves dynamically
    value = { "date_mode" => "yesterday" }
    assert_equal (Date.today - 1).to_s, SmartSuite::DateModeResolver.extract_date_value(value)
  end

  # ============================================
  # Tests for .dynamic_mode?
  # ============================================

  def test_dynamic_mode_returns_true_for_known_modes
    %w[today yesterday tomorrow one_week_ago one_week_from_now
       one_month_ago one_month_from_now start_of_week end_of_week
       start_of_month end_of_month].each do |mode|
      assert SmartSuite::DateModeResolver.dynamic_mode?(mode),
             "Expected '#{mode}' to be recognized as dynamic mode"
    end
  end

  def test_dynamic_mode_returns_false_for_unknown_modes
    refute SmartSuite::DateModeResolver.dynamic_mode?("exact_date")
    refute SmartSuite::DateModeResolver.dynamic_mode?("custom")
    refute SmartSuite::DateModeResolver.dynamic_mode?("2025-01-01")
  end

  def test_dynamic_mode_is_case_insensitive
    assert SmartSuite::DateModeResolver.dynamic_mode?("TODAY")
    assert SmartSuite::DateModeResolver.dynamic_mode?("Today")
  end
end
