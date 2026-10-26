# frozen_string_literal: true

require "ipaddr"

module GarminMcp
  ListenAddress = Data.define(:host, :port)

  # Where the HTTP transport listens (GARMIN_MCP_HOST, GARMIN_MCP_PORT). The host is an IP address or a host name;
  # an IPv6 address may be written in brackets and is kept without them, so authority adds them exactly once.
  class ListenAddress
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 8080
    HOST_NAME = /\A(?!-)[A-Za-z0-9_-]{1,63}(?<!-)(?:\.(?!-)[A-Za-z0-9_-]{1,63}(?<!-))*\z/

    # Reads only these two settings, so the container health check needs no secrets. Raises Config::Error when invalid.
    def self.from_env(env = ENV)
      reader = Config::EnvReader.new(env)
      read(reader).tap { reader.validate! }
    end

    # Adds any problem to the reader's errors.
    def self.read(reader)
      new(host: read_host(reader), port: reader.integer("GARMIN_MCP_PORT", DEFAULT_PORT, 1..65_535))
    end

    def self.read_host(reader)
      value = reader.string("GARMIN_MCP_HOST", DEFAULT_HOST)
      bare = value[/\A\[(.*)\]\z/, 1]
      return bare if bare && ip_address?(bare) && bare.include?(":")
      return value if !bare && (ip_address?(value) || host_name?(value))

      reader.errors << "GARMIN_MCP_HOST must be an IP address or host name (brackets are allowed only around an IPv6 address)"
      value
    end

    # IPAddr also accepts prefixes (10.0.0.0/8), zone IDs (fe80::1%eth0) and brackets, none of which can be bound here.
    def self.ip_address?(value)
      !value.match?(%r{[\[\]%/]}) && IPAddr.new(value) && true
    rescue IPAddr::Error
      false
    end

    # A dotted all-numeric name is a mistyped IPv4 address, not a host name.
    def self.host_name?(value) = value.length <= 253 && value.match?(HOST_NAME) && !value.match?(/\A[\d.]+\z/)

    private_class_method :read_host, :ip_address?, :host_name?

    # host:port, with an IPv6 address in brackets.
    def authority = host.include?(":") ? "[#{host}]:#{port}" : "#{host}:#{port}"

    def url(path = "") = "http://#{authority}#{path}"
  end
end
