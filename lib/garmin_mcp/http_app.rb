# frozen_string_literal: true

require "json"
require "mcp"

module GarminMcp
  # Rack application: an unauthenticated liveness probe at HealthCheck::PATH and the MCP endpoint, which runs the
  # SDK's Streamable HTTP transport in stateless JSON mode (no sessions, no server-held streams).
  class HttpApp
    MAX_REQUEST_BYTES = 1024 * 1024
    JSON_HEADERS = { "content-type" => "application/json", "cache-control" => "no-store" }.freeze

    def initialize(server:, config:, logger:)
      @path = config.path
      @logger = logger
      @guard = HostOriginGuard.new(allowed_hosts: config.allowed_hosts, allowed_origins: config.allowed_origins)
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        dns_rebinding_protection: false, # HostOriginGuard checks Host and Origin before the transport runs
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
      when HealthCheck::PATH
        env["REQUEST_METHOD"] == "GET" ? json(200, status: "ok", version: VERSION) : json(405, error: "method not allowed")
      when @path
        forbidden(env) || @transport.call(env)
      else
        json(404, error: "not found")
      end
    end

    # A rejection is logged with a hint, so a misconfigured deployment is explained instead of failing with a bare 403.
    def forbidden(env)
      case @guard.rejection(host: env["HTTP_HOST"], origin: env["HTTP_ORIGIN"])
      when :host
        @logger.warn("host_rejected", host: env["HTTP_HOST"], hint: "add the host to GARMIN_MCP_ALLOWED_HOSTS")
        json(403, error: "host not allowed")
      when :origin
        @logger.warn("origin_rejected", origin: env["HTTP_ORIGIN"], hint: "add the origin to GARMIN_MCP_ALLOWED_ORIGINS")
        json(403, error: "origin not allowed")
      end
    end

    def json(status, **body) = [status, JSON_HEADERS.dup, [JSON.generate(body)]]

    def log(env, status, started)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      level = env["PATH_INFO"] == HealthCheck::PATH ? :debug : :info
      @logger.public_send(level, "http_request", method: env["REQUEST_METHOD"], path: env["PATH_INFO"], status:, duration_ms:)
    end
  end
end
