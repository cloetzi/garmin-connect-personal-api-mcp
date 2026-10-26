# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  Config = GarminMcp::Config

  def config(transport: :http, **values) = Config.from_env(env(**values), transport:)

  def assert_config_error(pattern, transport: :http, **values)
    error = assert_raises(Config::Error) { config(transport:, **values) }
    assert_match pattern, error.message
  end

  def test_defaults
    config = config()

    assert_equal "https://personal.connectapi.garmin.com", config.base_url
    assert_equal "127.0.0.1", config.host
    assert_equal 8080, config.port
    assert_equal "/mcp", config.path
    assert_equal [TestHelpers::AUTH_TOKEN], config.auth_tokens
    refute config.auth_disabled
    assert_nil config.tools
  end

  def test_auth_token_is_required_for_http
    assert_config_error(/GARMIN_MCP_AUTH_TOKEN .* is required/, GARMIN_MCP_AUTH_TOKEN: nil)
  end

  def test_auth_can_be_disabled_explicitly
    config = config(GARMIN_MCP_AUTH_TOKEN: nil, GARMIN_MCP_AUTH_DISABLED: "true")

    assert config.auth_disabled
    assert_empty config.auth_tokens
  end

  def test_auth_disabled_and_token_conflict
    assert_config_error(/conflicts/, GARMIN_MCP_AUTH_DISABLED: "true")
  end

  def test_stdio_needs_no_auth_token
    assert_empty config(transport: :stdio, GARMIN_MCP_AUTH_TOKEN: nil).auth_tokens
  end

  def test_short_tokens_are_rejected
    assert_config_error(/at least 32 characters/, GARMIN_MCP_AUTH_TOKEN: "short")
  end

  def test_multiple_tokens_for_rotation
    second = "s" * 40

    assert_equal [TestHelpers::AUTH_TOKEN, second], config(GARMIN_MCP_AUTH_TOKEN: "#{TestHelpers::AUTH_TOKEN}, #{second}").auth_tokens
  end

  def test_secrets_from_files
    key_file = write_tempfile("key", "file-key\n")
    token_file = write_tempfile("token", "#{"f" * 40}\n")
    config = config(GARMIN_PERSONAL_API_KEY: nil, GARMIN_PERSONAL_API_KEY_FILE: key_file, GARMIN_MCP_AUTH_TOKEN: nil,
                    GARMIN_MCP_AUTH_TOKEN_FILE: token_file)

    assert_equal "file-key", config.api_key
    assert_equal ["f" * 40], config.auth_tokens
  end

  def test_secret_value_and_file_conflict
    assert_config_error(/only one of GARMIN_PERSONAL_API_KEY/, GARMIN_PERSONAL_API_KEY_FILE: "/dev/null")
  end

  def test_missing_secret_file
    assert_config_error(%r{cannot read /nonexistent}, GARMIN_PERSONAL_API_KEY: nil, GARMIN_PERSONAL_API_KEY_FILE: "/nonexistent")
  end

  def test_base_url_must_be_https_except_loopback
    assert_config_error(/must be an https URL/, GARMIN_PERSONAL_API_BASE_URL: "http://example.com")
    assert_equal "http://127.0.0.1:9", config(GARMIN_PERSONAL_API_BASE_URL: "http://127.0.0.1:9/").base_url
  end

  def test_reports_all_errors_at_once
    error = assert_raises(Config::Error) { config(GARMIN_PERSONAL_API_KEY: nil, GARMIN_MCP_PORT: "x", GARMIN_MCP_LOG_LEVEL: "loud") }

    assert_equal 3, error.message.scan(/^  - /).size
  end

  def test_mcp_path_cannot_shadow_the_health_check
    assert_config_error(%r{GARMIN_MCP_PATH cannot be /healthz}, GARMIN_MCP_PATH: "/healthz")
    assert_equal "/healthz/mcp", config(GARMIN_MCP_PATH: "/healthz/mcp").path
  end

  def test_listen_address_needs_no_secrets
    assert_equal ["127.0.0.1", 8080], Config.listen_address({})
    assert_equal ["::", 9000], Config.listen_address({ "GARMIN_MCP_HOST" => " :: ", "GARMIN_MCP_PORT" => "9000" })
  end

  def test_listen_address_is_validated_like_the_server
    error = assert_raises(Config::Error) { Config.listen_address({ "GARMIN_MCP_PORT" => "0" }) }

    assert_match(/GARMIN_MCP_PORT must be between 1 and 65535/, error.message)
  end

  def test_lists
    config = config(GARMIN_MCP_TOOLS: "sleep-service, get_daily_hrv", GARMIN_MCP_ALLOWED_HOSTS: "mcp.lan,")

    assert_equal %w[sleep-service get_daily_hrv], config.tools
    assert_equal ["mcp.lan"], config.allowed_hosts
  end

  def test_inspect_hides_secrets
    refute_includes config.inspect, TestHelpers::AUTH_TOKEN
    refute_includes config.inspect, FakeGarmin::API_KEY
  end
end
