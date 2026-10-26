# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class CatalogTest < Minitest::Test
  SNAPSHOT = File.join(TestHelpers::ROOT, "test/fixtures/tools.json")

  # Garmin's spec has no operationIds, so tool names must be curated: a new operation fails here
  # until data/overrides.yml names it.
  def test_every_operation_has_a_curated_name
    missing = spec.operations.reject { |operation| catalog.overrides.for(operation)["name"] }.map(&:key)

    assert_empty missing, "add names for these operations to data/overrides.yml"
  end

  # Range checks are inferred from the spec, but a new endpoint with dates must still be looked at: its span
  # limit (`max_days`, or null when Garmin states none) recorded, or the pair named, or `date_range: false`.
  def test_every_date_range_is_classified
    unclassified = catalog.tools.reject do |tool|
      setting = catalog.overrides.for(tool.operation)["date_range"]
      dates = tool.operation.parameters.count { |param| %w[date date-time].include?(param.schema["format"]) }
      tool.date_range ? setting.is_a?(Hash) && setting.key?("max_days") : dates < 2 || setting == false
    end

    assert_empty unclassified.map(&:operation).map(&:key), "classify these operations' date_range in data/overrides.yml"
  end

  # Span limits come from Garmin's documentation only, so they cannot drift from it or be invented.
  def test_range_limits_match_the_spec
    stated = catalog.tools.to_h do |tool|
      count, unit = tool.operation.description.to_s.match(/maximum of (\d+) (day|year)s?\b/)&.captures
      [tool.name, count && (unit == "year" ? Integer(count) * 366 : Integer(count))]
    end

    assert_equal stated, catalog.tools.to_h { |tool| [tool.name, tool.date_range&.max_days] }, "max_days must match the spec descriptions"
  end

  def test_infers_date_ranges_from_the_spec
    ranges = catalog.tools.to_h { |tool| [tool.name, tool.date_range&.then { |range| [range.start, range.end] }] }

    assert_equal %w[fromDate toDate], ranges["get_daily_hrv_summaries"]
    assert_equal %w[fromDate untilDate], ranges["get_wellness_activity_summaries"]
    assert_equal %w[startDate endDate], ranges["search_activities"]
    assert_nil ranges["get_menstrual_cycle_day_view"], "calendarDate and todayDate are not a range"
    assert_nil ranges["get_daily_sleep"]
  end

  def test_date_range_overrides
    path = write_tempfile("overrides.yml", <<~YAML)
      operations:
        GET /periodichealth-service/menstrualcycle/dayview/{calendarDate}:
          date_range: { start: calendarDate, end: todayDate, max_days: 7 }
        GET /hrv-service/hrv/daily/{fromDate}/{toDate}:
          date_range: false
    YAML
    tools = GarminMcp::Application.catalog(overrides_file: path).tools.to_h { |tool| [tool.name, tool] }

    assert_equal GarminMcp::ToolDefinition::DateRange.new(start: "calendarDate", end: "todayDate", max_days: 7),
                 tools["get_menstrual_cycle_day_view"].date_range
    assert_match(/Maximum range: 7 days/, tools["get_menstrual_cycle_day_view"].description)
    assert_nil tools["get_daily_hrv_summaries"].date_range
  end

  def test_date_range_overrides_must_fit_the_operation
    {
      "GET /sleep-service/sleep/dailySleep:\n    date_range: { max_days: 7 }" => /no date parameter pair/,
      "GET /sleep-service/sleep/dailySleepSummariesByDate:\n    date_range: { start: startDate }" => /invalid overrides/,
      "GET /wellness-service/wellness/bodyBattery/reports/daily:\n    date_range: { start: startDate, end: chunks }" => /chunks is not a date/
    }.each do |entry, message|
      path = write_tempfile("overrides.yml", "operations:\n  #{entry}\n")
      error = assert_raises(GarminMcp::Error) { GarminMcp::Application.catalog(overrides_file: path) }
      assert_match message, error.message
    end
  end

  def test_spec_is_read_only
    assert_equal ["get"], spec.operations.map(&:http_method).uniq
  end

  # Any change to the spec or the overrides shows up as a diff of test/fixtures/tools.json.
  # Regenerate with: UPDATE_SNAPSHOTS=1 bundle exec rake test
  def test_tool_manifest_matches_snapshot
    actual = "#{JSON.pretty_generate(catalog.manifest)}\n"
    File.write(SNAPSHOT, actual) if ENV["UPDATE_SNAPSHOTS"] == "1"

    assert_equal File.read(SNAPSHOT), actual, "tool manifest changed; review and run UPDATE_SNAPSHOTS=1 bundle exec rake test"
  end

  def test_download_is_disabled_by_default
    refute_includes catalog.select.map(&:name), "download_activity"
    assert_includes catalog.select(include: ["download_activity"]).map(&:name), "download_activity"
  end

  def test_select_by_service_and_exclude
    names = catalog.select(include: %w[sleep-service get_daily_hrv], exclude: ["get_daily_sleep_summaries"]).map(&:name)

    assert_equal %w[get_daily_hrv get_daily_sleep], names.sort
  end

  def test_select_rejects_unknown_names
    error = assert_raises(GarminMcp::Catalog::Error) { catalog.select(exclude: ["get_dialy_sleep"]) }
    assert_match(/get_dialy_sleep/, error.message)
  end

  def test_user_overrides_merge_on_top
    path = write_tempfile("overrides.yml", <<~YAML)
      operations:
        GET /sleep-service/sleep/dailySleep:
          description: Custom.
          parameters:
            date:
              description: Custom date.
    YAML
    custom = GarminMcp::Application.catalog(overrides_file: path).tools.find { |tool| tool.name == "get_daily_sleep" }

    assert_equal "Custom.", custom.description
    assert_equal "Custom date.", custom.input_schema.dig(:properties, "date", "description")
    assert_equal ["date"], custom.input_schema[:required], "bundled required flag is kept"
  end

  def test_overrides_must_match_the_spec
    path = write_tempfile("overrides.yml", "operations:\n  GET /nope:\n    name: nope\n")
    error = assert_raises(GarminMcp::Overrides::Error) { GarminMcp::Application.catalog(overrides_file: path) }
    assert_match(%r{GET /nope is not an operation}, error.message)

    path = write_tempfile("overrides.yml", "operations:\n  GET /sleep-service/sleep/dailySleep:\n    parameters:\n      day: {}\n")
    error = assert_raises(GarminMcp::Overrides::Error) { GarminMcp::Application.catalog(overrides_file: path) }
    assert_match(/no parameter day/, error.message)
  end

  def test_overrides_reject_unknown_keys
    path = write_tempfile("overrides.yml", "operations:\n  GET /sleep-service/sleep/dailySleep:\n    nmae: typo\n")
    assert_raises(GarminMcp::Overrides::Error) { GarminMcp::Application.catalog(overrides_file: path) }
  end

  def test_derived_name
    operation = spec.operation("GET /sleep-service/sleep/dailySleepSummariesByDate")

    assert_equal "get_sleep_service_sleep_daily_sleep_summaries_by_date", GarminMcp::Catalog.derived_name(operation)
  end
end
