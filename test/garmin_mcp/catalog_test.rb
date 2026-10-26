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
