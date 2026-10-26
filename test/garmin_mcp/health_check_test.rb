# frozen_string_literal: true

require_relative "../test_helper"
require "net/http"

class HealthCheckTest < Minitest::Test
  HealthCheck = GarminMcp::HealthCheck

  def test_wildcard_binds_are_probed_over_loopback_of_the_same_family
    assert_equal "127.0.0.1", HealthCheck.probe_host("0.0.0.0")
    assert_equal "::1", HealthCheck.probe_host("::")
    assert_equal "::1", HealthCheck.probe_host("0:0:0:0:0:0:0:0")
  end

  def test_specific_hosts_are_probed_as_is
    %w[127.0.0.1 172.20.0.5 ::1 fd00::5 localhost garmin-mcp].each do |host|
      assert_equal host, HealthCheck.probe_host(host)
    end
  end

  def test_url_follows_the_server_configuration
    assert_equal "http://127.0.0.1:8080/healthz", HealthCheck.url({})
    assert_equal "http://172.20.0.5:9000/healthz", HealthCheck.url({ "GARMIN_MCP_HOST" => "172.20.0.5", "GARMIN_MCP_PORT" => "9000" })
    assert_equal "http://[::1]:8080/healthz", HealthCheck.url({ "GARMIN_MCP_HOST" => "::" })
    assert_equal "http://[fd00::5]:8080/healthz", HealthCheck.url({ "GARMIN_MCP_HOST" => "[fd00::5]" })
  end

  def test_needs_no_secrets_but_validates_the_listen_address
    error = assert_raises(GarminMcp::Config::Error) { HealthCheck.url({ "GARMIN_MCP_PORT" => "0" }) }

    assert_match(/GARMIN_MCP_PORT must be between 1 and 65535/, error.message)
  end

  # Probes a real IPv6 listener the way bin/healthcheck does, checking the address is bracketed once in the Host header.
  def test_probes_an_ipv6_listener
    server = TCPServer.new("::1", 0)
    uri = URI(HealthCheck.url({ "GARMIN_MCP_HOST" => "::", "GARMIN_MCP_PORT" => server.addr[1].to_s }))

    Sync do |task|
      request = task.async { respond_ok(server.accept) }
      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 2) { |http| http.get(uri.path) }

      assert_instance_of Net::HTTPOK, response
      assert_match(%r{\AGET /healthz HTTP/1.1\r\n.*^host: \[::1\]:#{uri.port}\r$}im, request.wait)
    end
  rescue Errno::EADDRNOTAVAIL, Errno::EAFNOSUPPORT
    skip "no IPv6 loopback"
  ensure
    server&.close
  end

  private

  # Answers one request with 200 and returns the request head.
  def respond_ok(socket)
    lines = []
    lines << socket.gets until lines.last == "\r\n"
    socket.write("HTTP/1.1 200 OK\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
    lines.join
  ensure
    socket.close
  end
end
