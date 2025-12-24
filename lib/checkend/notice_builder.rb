# frozen_string_literal: true

module Checkend
  # NoticeBuilder converts Ruby exceptions into Notice objects.
  #
  # It handles backtrace cleaning, context merging, and user info extraction.
  #
  class NoticeBuilder
    MAX_BACKTRACE_LINES = 100
    MAX_MESSAGE_LENGTH = 10_000

    class << self
      # Build a Notice from an exception
      #
      # @param exception [Exception] the exception to report
      # @param context [Hash] additional context data
      # @param request [Hash] request information
      # @param user [Hash] user information
      # @param fingerprint [String] custom fingerprint for grouping
      # @param tags [Array<String>] tags for filtering
      # @return [Notice] the constructed notice
      def build(exception:, context: {}, request: nil, user: nil, fingerprint: nil, tags: [])
        notice = Notice.new

        # Error info
        notice.error_class = exception.class.name
        notice.message = truncate_message(exception.message)
        notice.backtrace = clean_backtrace(exception.backtrace || [])
        notice.fingerprint = fingerprint
        notice.tags = Array(tags)

        # Merge thread-local context with provided context
        notice.context = merge_context(context)
        notice.user = user || thread_local_user
        notice.request = request || {}

        # Environment
        notice.environment = Checkend.configuration.environment

        notice
      end

      private

      def clean_backtrace(backtrace)
        root_path = Checkend.configuration.root_path

        backtrace.first(MAX_BACKTRACE_LINES).map do |line|
          clean_backtrace_line(line, root_path)
        end
      end

      def clean_backtrace_line(line, root_path)
        return line unless root_path

        line.sub(root_path.to_s, '[PROJECT_ROOT]')
      end

      def truncate_message(message)
        return '' if message.nil?

        message = message.to_s
        return message if message.length <= MAX_MESSAGE_LENGTH

        "#{message[0, MAX_MESSAGE_LENGTH - 3]}..."
      end

      def merge_context(context)
        thread_context = thread_local_context
        thread_context.merge(context || {})
      end

      def thread_local_context
        ctx = Thread.current[:checkend_context]
        return {} unless ctx

        ctx.respond_to?(:to_h) ? ctx.to_h : {}
      end

      def thread_local_user
        ctx = Thread.current[:checkend_context]
        return nil unless ctx

        ctx.respond_to?(:user) ? ctx.user : nil
      end
    end
  end
end
