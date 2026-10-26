# frozen_string_literal: true

require_relative "../test_helper"

class HostOriginGuardTest < Minitest::Test
  def guard(hosts: [], origins: []) = GarminMcp::HostOriginGuard.new(allowed_hosts: hosts, allowed_origins: origins)

  def test_loopback_hosts_are_allowed_by_default
    %w[localhost localhost:8080 127.0.0.1 127.0.0.1:8080 [::1] [::1]:8080 LOCALHOST:8080].each do |host|
      assert_nil guard.rejection(host:, origin: nil), host
    end
  end

  def test_rejects_other_hosts
    %w[evil.example evil.example:8080 localhost.evil.example [::2]:8080 [::1].evil.example].each do |host|
      assert_equal :host, guard.rejection(host:, origin: nil), host
    end
  end

  def test_allowed_host_entries_match_name_or_host_and_port
    guard = guard(hosts: %w[mcp.lan proxy.lan:8443])

    assert_nil guard.rejection(host: "MCP.lan:9000", origin: nil)
    assert_nil guard.rejection(host: "proxy.lan:8443", origin: nil)
    assert_equal :host, guard.rejection(host: "proxy.lan:9000", origin: nil)
  end

  def test_missing_host_is_allowed_and_empty_host_is_not
    assert_nil guard.rejection(host: nil, origin: nil)
    assert_equal :host, guard.rejection(host: "", origin: nil)
  end

  def test_wildcard_host_allows_any_host
    assert_nil guard(hosts: ["*"]).rejection(host: "anything.example", origin: nil)
  end

  def test_missing_origin_is_allowed
    assert_nil guard.rejection(host: "localhost:8080", origin: nil)
  end

  def test_same_origin_is_allowed
    assert_nil guard.rejection(host: "localhost:8080", origin: "http://localhost:8080")
    assert_nil guard.rejection(host: "[::1]:8080", origin: "http://[::1]:8080")
    assert_nil guard(hosts: ["mcp.example"]).rejection(host: "mcp.example", origin: "https://MCP.example:443")
    assert_nil guard(hosts: ["mcp.example"]).rejection(host: "mcp.example:80", origin: "http://mcp.example")
  end

  def test_rejects_foreign_origins
    ["https://evil.example", "http://localhost:9999", "null", "http://localhost:8080/path", "file://localhost:8080"].each do |origin|
      assert_equal :origin, guard.rejection(host: "localhost:8080", origin:), origin
    end
    assert_equal :origin, guard.rejection(host: nil, origin: "http://localhost")
  end

  def test_allowed_origins
    guard = guard(origins: ["https://App.example"])

    assert_nil guard.rejection(host: "localhost:8080", origin: "https://app.example")
    assert_equal :origin, guard.rejection(host: "localhost:8080", origin: "http://app.example")
  end

  def test_wildcard_host_still_checks_origins
    guard = guard(hosts: ["*"], origins: ["https://app.example"])

    assert_equal :origin, guard.rejection(host: "mcp.example", origin: "https://evil.example")
    assert_nil guard.rejection(host: "mcp.example", origin: "https://app.example")
    assert_nil guard.rejection(host: "mcp.example", origin: "https://mcp.example")
    assert_nil guard.rejection(host: "mcp.example", origin: nil)
  end
end
