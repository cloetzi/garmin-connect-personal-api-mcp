# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"

class CLITest < Minitest::Test
  BIN = File.join(TestHelpers::ROOT, "bin/garmin-mcp")
  NO_CREDENTIALS = { GARMIN_PERSONAL_API_KEY: nil, GARMIN_MCP_AUTH_TOKEN: nil }.freeze

  # Runs bin/garmin-mcp with only the given Garmin settings, ignoring any in the developer's environment.
  def garmin_mcp(*, **values)
    cleared = ENV.keys.grep(/\AGARMIN_/).to_h { |key| [key, nil] }
    Open3.capture3(cleared.merge(env(**values)), RbConfig.ruby, BIN, *)
  end

  def test_check_config_defaults_to_http
    stdout, _stderr, status = garmin_mcp("check-config")

    assert_predicate status, :success?
    assert_match(/\AConfiguration OK for the http transport: \d+ tools enabled/, stdout)
    assert_match(/^MCP authentication: bearer token$/, stdout)
  end

  def test_check_config_http_requires_a_token
    _stdout, stderr, status = garmin_mcp("check-config", "http", GARMIN_MCP_AUTH_TOKEN: nil)

    assert_equal 78, status.exitstatus
    assert_match(/GARMIN_MCP_AUTH_TOKEN .* is required/, stderr)
  end

  def test_check_config_stdio_needs_no_token
    stdout, _stderr, status = garmin_mcp("check-config", "stdio", GARMIN_MCP_AUTH_TOKEN: nil)

    assert_predicate status, :success?
    assert_match(/\AConfiguration OK for the stdio transport: /, stdout)
    assert_match(/^MCP authentication: not used \(stdio\)$/, stdout)
  end

  def test_check_config_warns_about_a_non_default_base_url
    _stdout, stderr, status = garmin_mcp("check-config", GARMIN_PERSONAL_API_BASE_URL: "http://127.0.0.1:9")

    assert_predicate status, :success?
    assert_match(%r{WARN  non_default_garmin_base_url base_url=http://127\.0\.0\.1:9 }, stderr)
  end

  def test_check_config_does_not_warn_about_the_default_base_url
    _stdout, stderr, status = garmin_mcp("check-config")

    assert_predicate status, :success?
    refute_match(/non_default_garmin_base_url/, stderr)
  end

  def test_check_config_rejects_a_foreign_base_url
    _stdout, stderr, status = garmin_mcp("check-config", GARMIN_PERSONAL_API_BASE_URL: "https://example.com")

    assert_equal 78, status.exitstatus
    assert_match(/GARMIN_PERSONAL_API_BASE_URL must be/, stderr)
  end

  def test_check_config_rejects_an_unknown_transport
    _stdout, stderr, status = garmin_mcp("check-config", "sse")

    assert_equal 64, status.exitstatus
    assert_match(/unknown transport: sse/, stderr)
  end

  def test_tools_needs_no_credentials_and_treats_an_empty_overrides_file_as_unset
    names = tools_manifest(GARMIN_MCP_OVERRIDES_FILE: "").map { |tool| tool["name"] }

    assert_equal catalog.tools.map(&:name), names
  end

  def test_tools_applies_the_overrides_file
    path = write_tempfile("overrides.yml", <<~YAML)
      operations:
        GET /sleep-service/sleep/dailySleepSummariesByDate:
          title: Custom sleep title
    YAML
    sleep = tools_manifest(GARMIN_MCP_OVERRIDES_FILE: path).find { |tool| tool["name"] == "get_daily_sleep_summaries" }

    assert_equal "Custom sleep title", sleep["title"]
  end

  def test_tools_lists_the_whole_catalog_regardless_of_selection
    names = tools_manifest(GARMIN_MCP_TOOLS: "sleep-service").map { |tool| tool["name"] }

    assert_includes names, "download_activity"
  end

  private

  def tools_manifest(**values)
    stdout, stderr, status = garmin_mcp("tools", **NO_CREDENTIALS, **values)

    assert_predicate status, :success?, stderr
    JSON.parse(stdout)
  end
end
