# frozen_string_literal: true

module GarminMcp
  module Garmin
    # Authenticated, read-only access to the Personal API.
    class Client
      def initialize(http:, tokens:)
        @http = http
        @tokens = tokens
      end

      def get(path, accept: "application/json")
        token = @tokens.token
        response = @http.request("GET", path, headers(token, accept))
        return response unless response.status == 401

        # The token may have been revoked or expired early: retry once with a fresh one.
        @tokens.invalidate(token)
        @http.request("GET", path, headers(@tokens.token, accept))
      end

      private

      def headers(token, accept) = [["authorization", "Bearer #{token}"], ["accept", accept]]
    end
  end
end
