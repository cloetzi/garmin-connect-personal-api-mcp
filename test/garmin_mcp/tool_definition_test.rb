# frozen_string_literal: true

require_relative "../test_helper"

class ToolDefinitionTest < Minitest::Test
  InvalidArguments = GarminMcp::ToolDefinition::InvalidArguments

  def test_builds_path_parameters
    request = tool("get_daily_steps").build_request(startDate: "2026-10-01", endDate: "2026-10-28")

    assert_equal "/usersummary-service/stats/steps/daily/2026-10-01/2026-10-28", request.to_s
  end

  def test_builds_query_with_override_defaults_and_repeated_arrays
    request = tool("search_activities").build_request(activityType: "running", excludedActivitySubType: %w[treadmill_running indoor_running])

    assert_equal "/activitylist-service/activities/search/activities?limit=20&activityType=running&" \
                 "excludedActivitySubType=treadmill_running&excludedActivitySubType=indoor_running", request.to_s
  end

  def test_spec_defaults_are_documented_but_not_sent
    definition = tool("search_activities")

    assert_equal 0, definition.input_schema.dig(:properties, "start", "default")
    refute_includes definition.build_request({}).to_s, "start="
  end

  def test_path_values_are_escaped
    request = tool("get_activity").build_request(activityId: "1/../../x")

    assert_equal "/activity-service/activity/1%2F..%2F..%2Fx", request.path
  end

  def test_rejects_invalid_dates
    error = assert_raises(InvalidArguments) { tool("get_daily_sleep").build_request(date: "2026-02-30") }
    assert_match(/valid calendar date/, error.message)
  end

  def test_enforces_date_range_limits
    definition = tool("get_daily_steps")

    assert_raises(InvalidArguments) { definition.build_request(startDate: "2026-10-02", endDate: "2026-10-01") }
    error = assert_raises(InvalidArguments) { definition.build_request(startDate: "2026-01-01", endDate: "2026-01-29") }
    assert_match(/at most 28 days/, error.message)
    definition.build_request(startDate: "2026-01-01", endDate: "2026-01-28")
  end

  def test_checks_order_of_ranges_without_a_limit
    definition = tool("get_daily_hrv_summaries")

    error = assert_raises(InvalidArguments) { definition.build_request(fromDate: "2026-10-02", toDate: "2026-10-01") }
    assert_equal "fromDate must not be after toDate", error.message
    definition.build_request(fromDate: "2016-01-01", toDate: "2026-10-01")
  end

  def test_checks_order_of_optional_query_ranges
    definition = tool("search_activities")

    assert_raises(InvalidArguments) { definition.build_request(startDate: "2026-10-02", endDate: "2026-10-01") }
    definition.build_request(startDate: "2026-10-02")
  end

  def test_input_schema
    schema = tool("get_daily_sleep").input_schema

    assert_equal ["date"], schema[:required]
    refute schema[:additionalProperties]
    assert_equal({ "type" => "string", "format" => "date", "pattern" => "^\\d{4}-\\d{2}-\\d{2}$",
                   "description" => "Calendar date (YYYY-MM-DD) of the morning the sleep ended." }, schema[:properties]["date"])
  end

  def test_binary_operations
    assert_predicate tool("download_activity"), :binary?
    refute_predicate tool("get_activity"), :binary?
  end
end
