# frozen_string_literal: true

module GarminMcp
  class Config
    # Typed reads of environment variables. A malformed value is recorded in errors and replaced by the default,
    # so validate! can report every problem at once.
    class EnvReader
      attr_reader :errors

      def initialize(env)
        @env = env
        @errors = []
      end

      def validate!
        raise Error, "invalid configuration:\n  - #{errors.join("\n  - ")}" if errors.any?
      end

      def string(name, default)
        value = @env[name].to_s.strip
        value.empty? ? default : value
      end

      def list(name) = @env[name].to_s.split(",").map(&:strip).reject(&:empty?).freeze

      def integer(name, default, range)
        raw = @env[name].to_s.strip
        return default if raw.empty?

        value = Integer(raw, 10)
        return value if range.cover?(value)

        errors << "#{name} must be between #{range.min} and #{range.max}"
        default
      rescue ArgumentError
        errors << "#{name} must be an integer"
        default
      end

      def boolean(name, default)
        case @env[name].to_s.strip.downcase
        when "" then default
        when "true", "1", "yes" then true
        when "false", "0", "no" then false
        else
          errors << "#{name} must be true or false"
          default
        end
      end

      def choice(name, default, choices)
        value = string(name, default).downcase
        return value if choices.include?(value)

        errors << "#{name} must be one of #{choices.join(", ")}"
        default
      end

      # Read from name, or from the file named by name_FILE (e.g. a Docker secret); setting both is an error.
      def secret(name, required: false)
        file_name = "#{name}_FILE"
        direct = string(name, "")
        file = string(file_name, "")
        unless direct.empty? || file.empty?
          errors << "set only one of #{name} and #{file_name}"
          return
        end

        value = file.empty? ? direct : read_secret_file(file_name, file)
        errors << "#{name} (or #{file_name}) is required" if required && value.to_s.empty?
        value.to_s.empty? ? nil : value
      end

      private

      def read_secret_file(name, path)
        File.read(path).strip
      rescue SystemCallError => e
        errors << "#{name}: cannot read #{path} (#{e.class.name.split("::").last})"
        nil
      end
    end
  end
end
