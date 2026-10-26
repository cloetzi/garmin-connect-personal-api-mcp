# frozen_string_literal: true

module GarminMcp
  module Garmin
    # Authenticated, read-only access to the Personal API.
    class Client
      def initialize(http:, tokens:)
        @http = http
        @tokens = tokens
      end

      def get(path, accept: "application/json", max_body_bytes: nil)
        token = @tokens.token
        response = @http.request("GET", path, headers(token, accept), max_body_bytes:)
        return response unless response.status == 401

        # The token may have expired early or been revoked: retry once with a fresh one, unless the token is so new
        # that the 401 must be about this endpoint. A 401 returned to the caller thus means the key works but not here.
        retry_token = @tokens.rejected(token) or return response
        @http.request("GET", path, headers(retry_token, accept), max_body_bytes:)
      end

      private

      def headers(token, accept) = [["authorization", "Bearer #{token}"], ["accept", accept]]
    end
  end
end
