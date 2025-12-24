# frozen_string_literal: true

module Checkend
  module Filters
    # IgnoreFilter determines whether an exception should be ignored.
    #
    # It checks the exception against the configured ignored_exceptions list,
    # supporting class names, classes, and regular expressions.
    #
    class IgnoreFilter
      def initialize(config)
        @ignored_exceptions = config.ignored_exceptions
      end

      # Check if an exception should be ignored
      #
      # @param exception [Exception] the exception to check
      # @return [Boolean] true if should be ignored
      def ignore?(exception)
        exception_class_name = exception.class.name

        @ignored_exceptions.any? do |pattern|
          matches?(exception, exception_class_name, pattern)
        end
      end

      private

      def matches?(exception, class_name, pattern)
        case pattern
        when String
          matches_string?(exception, class_name, pattern)
        when Class
          exception.is_a?(pattern)
        when Regexp
          pattern.match?(class_name)
        else
          false
        end
      end

      def matches_string?(exception, class_name, pattern)
        # Exact match
        return true if class_name == pattern

        # Check ancestors
        exception.class.ancestors.any? { |ancestor| ancestor.name == pattern }
      end
    end
  end
end
