# frozen_string_literal: true

module GarminMcp
  module Garmin
    Response = Data.define(:status, :content_type, :body, :retry_after) do
      def success? = (200..299).cover?(status)
      def json? = content_type.to_s.include?("json")
    end
  end
end
