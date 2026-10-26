# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"

class CLITest < Minitest::Test
  BIN = File.join(TestHelpers::ROOT, "bin/garmin-mcp")

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

  def test_check_config_rejects_an_unknown_transport
    _stdout, stderr, status = garmin_mcp("check-config", "sse")

    assert_equal 64, status.exitstatus
    assert_match(/unknown transport: sse/, stderr)
  end
end
