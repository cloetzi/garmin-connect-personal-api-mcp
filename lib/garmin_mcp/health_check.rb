# frozen_string_literal: true

require "ipaddr"

module GarminMcp
  # The unauthenticated liveness endpoint served beside MCP, and where the container health check (bin/healthcheck)
  # reaches it. Loads no more than ListenAddress, because Docker runs the check every few seconds.
  module HealthCheck
    PATH = "/healthz"

    # URL to probe for the listener configured in env; raises Config::Error when the listen address is invalid.
    def self.url(env = ENV) = target(env).url(PATH)

    def self.target(env = ENV)
      address = ListenAddress.from_env(env)
      address.with(host: probe_host(address.host))
    end

    # A wildcard bind accepts connections on every local address, so it is probed over loopback of the same family;
    # any other host is probed as is.
    def self.probe_host(host)
      address = IPAddr.new(host)
      return host unless address.to_i.zero?

      address.ipv4? ? "127.0.0.1" : "::1"
    rescue IPAddr::Error
      host
    end
  end
end
