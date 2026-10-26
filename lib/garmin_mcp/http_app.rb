# frozen_string_literal: true

require "json"
require "mcp"

module GarminMcp
  # Rack application: an unauthenticated liveness probe at /healthz and the MCP endpoint, which runs the
  # SDK's Streamable HTTP transport in stateless JSON mode (no sessions, no server-held streams).
  class HttpApp
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    MAX_REQUEST_BYTES = 1024 * 1024
    JSON_HEADERS = { "content-type" => "application/json", "cache-control" => "no-store" }.freeze

    def initialize(server:, config:, logger:)
      @path = config.path
      @logger = logger
      @any_host = config.allowed_hosts.include?("*")
      @allowed_hosts = (LOOPBACK_HOSTS + config.allowed_hosts).map(&:downcase).freeze
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        dns_rebinding_protection: !@any_host,
        allowed_hosts: config.allowed_hosts - ["*"],
        allowed_origins: config.allowed_origins,
        max_request_bytes: MAX_REQUEST_BYTES,
        token_verifier: config.auth_disabled ? nil : StaticTokenVerifier.new(config.auth_tokens)
      )
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = route(env)
      log(env, response.first, started)
      response
    end

    private

    def route(env)
      case env["PATH_INFO"]
      when "/healthz"
        env["REQUEST_METHOD"] == "GET" ? json(200, status: "ok", version: VERSION) : json(405, error: "method not allowed")
      when @path
        return host_rejected(env) unless host_allowed?(env["HTTP_HOST"])

        @transport.call(env)
      else
        json(404, error: "not found")
      end
    end

    # Mirrors the SDK's DNS rebinding check so a rejected Host is explained in the logs instead of a bare 403.
    def host_allowed?(header)
      return true if @any_host
      return false if header.to_s.empty?

      header = header.downcase
      name = header.start_with?("[") ? header[/\A\[([^\]]+)\]/, 1] : header.split(":", 2).first
      @allowed_hosts.include?(header) || @allowed_hosts.include?(name)
    end

    def host_rejected(env)
      @logger.warn("host_rejected", host: env["HTTP_HOST"].to_s, hint: "add the host to GARMIN_MCP_ALLOWED_HOSTS")
      json(403, error: "host not allowed")
    end

    def json(status, **body) = [status, JSON_HEADERS.dup, [JSON.generate(body)]]

    def log(env, status, started)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      level = env["PATH_INFO"] == "/healthz" ? :debug : :info
      @logger.public_send(level, "http_request", method: env["REQUEST_METHOD"], path: env["PATH_INFO"], status:, duration_ms:)
    end
  end
end
