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
      # Printable ASCII without whitespace, as it goes into a header; matched on bytes as the body may not be UTF-8.
      TOKEN_FORMAT = /\A[!-~]+\z/n
      # Garmin also answers 401 for endpoints the key may not use, so a token this young is kept despite a 401.
      REJECTION_MIN_AGE = 300
      # After a failed exchange, callers get the same error for this long instead of asking Garmin again.
      FAILURE_BACKOFF = 10

      Token = Data.define(:value, :issued_at, :expires_at)
      Failure = Data.define(:error, :at)

      def initialize(http:, api_key:, logger:, clock: -> { Process.clock_gettime(Process::CLOCK_REALTIME) })
        @http = http
        @api_key = api_key
        @logger = logger
        @clock = clock
        @mutex = Mutex.new
        @token = nil
        @failure = nil
      end

      # Only one fiber performs the exchange; concurrent callers wait for its result.
      def token
        current = @token
        return current.value if usable?(current)

        @mutex.synchronize do
          renew unless usable?(@token)
          @token.value
        end
      end

      # Called after Garmin answered 401 to a request made with `value`. Returns the token to retry with, or nil
      # when retrying cannot help because the token is too young to have expired or been revoked.
      def rejected(value)
        @mutex.synchronize do
          # Another fiber already replaced the rejected token: retry with its replacement.
          return @token.value if @token && @token.value != value && usable?(@token)

          if @token&.value == value && @clock.call - @token.issued_at < REJECTION_MIN_AGE
            @logger.info("garmin_token_kept_after_401", age: (@clock.call - @token.issued_at).round)
            return
          end

          @logger.info("garmin_token_renewed_after_401")
          @token = nil # a key revoked along with its token fails the exchange; do not keep using the token
          renew.value
        end
      end

      def inspect = "#<#{self.class.name}>"

      private

      # Callers hold the mutex, so fibers queued behind a failed exchange get its error without asking Garmin again.
      def renew
        raise @failure.error.class, @failure.error.message if @failure && @clock.call - @failure.at < FAILURE_BACKOFF

        @token = remembering_failure { exchange }
      end

      def remembering_failure
        yield.tap { @failure = nil }
      rescue Error => e
        @failure = Failure.new(error: e, at: @clock.call)
        raise
      end

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

        value = response.body.b.strip
        raise Error, "Garmin token exchange returned an unexpected response" unless value.match?(TOKEN_FORMAT)

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
        claims = JSON.parse(payload.tr("-_", "+/").unpack1("m"))
        Float(claims["exp"]) if claims.is_a?(Hash)
      rescue ArgumentError, TypeError, JSON::ParserError
        nil
      end
    end
  end
end
