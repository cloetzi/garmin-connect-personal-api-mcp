# frozen_string_literal: true

require_relative "../test_helper"

class ListenAddressTest < Minitest::Test
  ListenAddress = GarminMcp::ListenAddress

  def address(host) = ListenAddress.from_env({ "GARMIN_MCP_HOST" => host })

  def assert_invalid_host(host)
    error = assert_raises(GarminMcp::Config::Error) { address(host) }
    assert_match(/GARMIN_MCP_HOST must be an IP address or host name/, error.message)
  end

  def test_defaults_and_needs_no_other_setting
    assert_equal ListenAddress.new(host: "127.0.0.1", port: 8080), ListenAddress.from_env({})
    assert_equal ListenAddress.new(host: "::", port: 9000), ListenAddress.from_env({ "GARMIN_MCP_HOST" => " :: ", "GARMIN_MCP_PORT" => "9000" })
  end

  def test_accepts_ip_addresses_and_host_names
    %w[0.0.0.0 172.20.0.5 :: ::1 fd00::5 ::ffff:127.0.0.1 localhost garmin-mcp garmin_mcp mcp.example.com].each do |host|
      assert_equal host, address(host).host
    end
  end

  def test_bracketed_ipv6_addresses_are_stored_bare
    assert_equal "::1", address("[::1]").host
    assert_equal "fd00::5", address("[fd00::5]").host
  end

  def test_rejects_anything_else
    ["[127.0.0.1]", "[localhost]", "[::1", "::1]", "[[::1]]", "10.0.0.0/8", "fe80::1%eth0", "300.1.1.1", "1.2.3",
     "host:8080", "http://localhost", "-garmin", "garmin-", "garmin..mcp", "a b", "#{"a" * 64}.example"].each do |host|
      assert_invalid_host(host)
    end
  end

  def test_reports_host_and_port_together
    error = assert_raises(GarminMcp::Config::Error) do
      ListenAddress.from_env({ "GARMIN_MCP_HOST" => "[localhost]", "GARMIN_MCP_PORT" => "port" })
    end

    assert_match(/GARMIN_MCP_HOST/, error.message)
    assert_match(/GARMIN_MCP_PORT must be an integer/, error.message)
  end

  def test_authority_and_url_bracket_ipv6_once
    assert_equal "127.0.0.1:8080", ListenAddress.new(host: "127.0.0.1", port: 8080).authority
    assert_equal "localhost:8080", ListenAddress.new(host: "localhost", port: 8080).authority
    assert_equal "[::1]:8080", address("[::1]").authority
    assert_equal "http://[::]:9000/mcp", ListenAddress.new(host: "::", port: 9000).url("/mcp")
    assert_equal "http://0.0.0.0:8080", ListenAddress.new(host: "0.0.0.0", port: 8080).url
  end
end
