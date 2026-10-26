# frozen_string_literal: true

module GarminMcp
  # Validates the Host and Origin headers of MCP requests against DNS rebinding and cross-site browser requests.
  # It replaces the SDK's check, which is all-or-nothing: `*` in the allowed hosts must relax only the Host check
  # while foreign origins stay rejected.
  class HostOriginGuard
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    def initialize(allowed_hosts:, allowed_origins:)
      @any_host = allowed_hosts.include?("*")
      @allowed_hosts = (LOOPBACK_HOSTS + allowed_hosts).map(&:downcase).freeze
      @allowed_origins = allowed_origins.map(&:downcase).freeze
    end

    # Returns :host or :origin when the request must be rejected, nil when it may proceed.
    def rejection(host:, origin:)
      return :host unless host_allowed?(host)

      :origin unless origin_allowed?(origin, host)
    end

    private

    # A request without a Host header is allowed: browsers, the only clients a rebinding attack can drive, always
    # send one. Entries match the bare host name (any port) or the full host:port.
    def host_allowed?(host)
      return true if @any_host || host.nil?

      host = host.downcase
      @allowed_hosts.include?(host) || @allowed_hosts.include?(hostname(host))
    end

    # A request without an Origin header comes from a non-browser client (browsers send one on every cross-origin
    # request and on every POST) and is allowed.
    def origin_allowed?(origin, host)
      return true if origin.nil?

      origin = origin.downcase
      @allowed_origins.include?(origin) || same_origin?(origin, host)
    end

    # `[::1]:8080` becomes `::1`, `127.0.0.1:8080` becomes `127.0.0.1`.
    def hostname(host) = host.start_with?("[") ? host[/\A\[([^\]]+)\](:\d*)?\z/, 1] : host.split(":", 2).first

    # Compares the Origin's host:port with the Host header, ignoring the scheme's default port on both sides.
    # The scheme itself cannot be compared: behind a TLS-terminating proxy the server only sees plain HTTP.
    def same_origin?(origin, host)
      authority = origin[%r{\Ahttps?://([^/]+)\z}, 1]
      return false if authority.nil? || host.nil?

      default_port = origin.start_with?("https://") ? ":443" : ":80"
      authority.delete_suffix(default_port) == host.downcase.delete_suffix(default_port)
    end
  end
end
