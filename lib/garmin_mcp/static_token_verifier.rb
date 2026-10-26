# frozen_string_literal: true

require "digest"
require "mcp"
require "openssl"

module GarminMcp
  # Bearer token check for the HTTP transport, plugged into the SDK's OAuth resource-server hook so the
  # SDK handles header parsing and RFC 6750 challenges. Accepts several tokens to allow rotation.
  class StaticTokenVerifier
    def initialize(tokens)
      raise ArgumentError, "at least one token is required" if tokens.empty?

      @digests = tokens.map { |token| Digest::SHA256.digest(token) }.freeze
    end

    def verify(token)
      digest = Digest::SHA256.digest(token.to_s)
      # Compare digests in constant time, and against every configured token, so timing reveals nothing.
      matched = @digests.map { |candidate| OpenSSL.fixed_length_secure_compare(candidate, digest) }.any?
      raise MCP::Server::OAuth::InvalidTokenError unless matched

      MCP::Server::OAuth::AccessToken.new(token:, subject: "static-token")
    end

    def inspect = "#<#{self.class.name} tokens=#{@digests.size}>"
  end
end
