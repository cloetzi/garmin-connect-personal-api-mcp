# frozen_string_literal: true

require "json"

module GarminMcp
  module Garmin
    # Exchanges the personal API key for a bearer token and caches it in memory. Garmin has no
    # refresh tokens: a new token is obtained with the key again before the current one expires.
    class TokenProvider
      TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token"
      REFRESH_WINDOW = 3600
      FALLBACK_TTL = 3600

      Token = Data.define(:value, :issued_at, :expires_at)

      def initialize(http:, api_key:, logger:, clock: -> { Process.clock_gettime(Process::CLOCK_REALTIME) })
        @http = http
        @api_key = api_key
        @logger = logger
        @clock = clock
        @mutex = Mutex.new
        @token = nil
      end

      # Only one fiber performs the exchange; concurrent callers wait for its result.
      def token
        current = @token
        return current.value if usable?(current)

        @mutex.synchronize do
          @token = exchange unless usable?(@token)
          @token.value
        end
      end

      # Drops the cached token after Garmin rejected it, unless another fiber already replaced it.
      def invalidate(value)
        @mutex.synchronize { @token = nil if @token&.value == value }
      end

      def inspect = "#<#{self.class.name}>"

      private

      def usable?(token)
        return false unless token

        lifetime = token.expires_at - token.issued_at
        token.expires_at - @clock.call > [REFRESH_WINDOW, lifetime / 2].min
      end

      def exchange
        response = @http.request("POST", TOKEN_PATH, [["authorization", "ApiKey #{@api_key}"], ["accept", "*/*"]])
        if [400, 401, 403].include?(response.status)
          raise AuthenticationError, "Garmin rejected the personal API key (HTTP #{response.status}); " \
                                     "it may be mistyped, expired or revoked. Create a new key in Garmin Connect."
        end
        raise Error, "Garmin token exchange failed with HTTP #{response.status}" unless response.success?

        value = response.body.strip
        raise Error, "Garmin token exchange returned an unexpected response" if value.empty? || value.match?(/\s/)

        now = @clock.call
        expires_at = jwt_expiration(value)
        unless expires_at && expires_at > now
          @logger.warn("garmin_token_without_expiry", assumed_ttl: FALLBACK_TTL)
          expires_at = now + FALLBACK_TTL
        end
        @logger.info("garmin_token_obtained", expires_in: (expires_at - now).round)
        Token.new(value:, issued_at: now, expires_at:)
      end

      # Reads the `exp` claim without verifying the signature; Garmin verifies the token, we only schedule renewal.
      def jwt_expiration(value)
        payload = value.split(".")[1] or return
        Float(JSON.parse(payload.tr("-_", "+/").unpack1("m"))["exp"])
      rescue ArgumentError, TypeError, JSON::ParserError
        nil
      end
    end
  end
end
