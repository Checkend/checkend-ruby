# frozen_string_literal: true

module Checkend
  module Filters
    # SanitizeFilter scrubs sensitive data from hashes before sending.
    #
    # It recursively traverses hashes and arrays, replacing values
    # for keys that match the configured filter patterns.
    #
    class SanitizeFilter
      FILTERED = '[FILTERED]'
      TRUNCATE_LIMIT = 10_000
      MAX_DEPTH = 10

      def initialize(config)
        @filter_keys = config.filter_keys.map { |k| k.to_s.downcase }
        @filter_pattern = build_pattern(@filter_keys)
      end

      # Sanitize a hash, scrubbing sensitive values
      #
      # @param data [Hash, Array, Object] the data to sanitize
      # @return [Hash, Array, Object] sanitized copy
      def call(data)
        sanitize(deep_dup(data), 0)
      end

      private

      def sanitize(obj, depth)
        return FILTERED if depth > MAX_DEPTH

        case obj
        when Hash
          sanitize_hash(obj, depth)
        when Array
          obj.map { |item| sanitize(item, depth + 1) }
        when String
          truncate_string(obj)
        else
          obj
        end
      end

      def sanitize_hash(hash, depth)
        hash.each do |key, value|
          string_key = key.to_s
          hash[key] = if should_filter?(string_key)
                        FILTERED
                      else
                        sanitize(value, depth + 1)
                      end
        end
        hash
      end

      def should_filter?(key)
        return false if key.nil?

        lowercase_key = key.to_s.downcase
        @filter_pattern.match?(lowercase_key)
      end

      def build_pattern(keys)
        return /(?!)/ if keys.empty? # Never match if no keys

        patterns = keys.map { |k| Regexp.escape(k) }
        Regexp.new(patterns.join('|'), Regexp::IGNORECASE)
      end

      def truncate_string(str)
        return str if str.length <= TRUNCATE_LIMIT

        "#{str[0, TRUNCATE_LIMIT - 13]}...[TRUNCATED]"
      end

      def deep_dup(obj)
        case obj
        when Hash
          obj.transform_keys(&:itself).transform_values { |v| deep_dup(v) }
        when Array
          obj.map { |item| deep_dup(item) }
        when String
          obj.dup
        else
          obj
        end
      end
    end
  end
end
