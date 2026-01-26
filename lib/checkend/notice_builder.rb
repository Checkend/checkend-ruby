# frozen_string_literal: true

module Checkend
  # NoticeBuilder converts Ruby exceptions into Notice objects.
  #
  # It handles backtrace cleaning, context merging, and user info extraction.
  #
  class NoticeBuilder
    MAX_BACKTRACE_LINES = 100
    MAX_MESSAGE_LENGTH = 10_000

    # Default error class for custom notifications without an exception
    DEFAULT_ERROR_CLASS = 'Checkend::Notice'

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

      # Build a Notice from a message string (custom notification without exception)
      #
      # @param message [String] the notification message
      # @param error_class [String] custom error class name (defaults to 'Checkend::Notice')
      # @param context [Hash] additional context data
      # @param request [Hash] request information
      # @param user [Hash] user information
      # @param fingerprint [String] custom fingerprint for grouping
      # @param tags [Array<String>] tags for filtering
      # @return [Notice] the constructed notice
      def build_from_message(message, error_class: nil, context: {}, request: nil, user: nil,
                             fingerprint: nil, tags: [])
        notice = Notice.new

        # Error info - no backtrace for custom notifications
        notice.error_class = error_class || DEFAULT_ERROR_CLASS
        notice.message = truncate_message(message)
        notice.backtrace = []
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

      # Build a Notice from a hash (custom notification with full control)
      #
      # @param hash [Hash] the notification data
      # @option hash [String] :error_class custom error class name
      # @option hash [String] :message the notification message
      # @option hash [Array<String>] :backtrace optional backtrace
      # @param context [Hash] additional context data
      # @param request [Hash] request information
      # @param user [Hash] user information
      # @param fingerprint [String] custom fingerprint for grouping
      # @param tags [Array<String>] tags for filtering
      # @return [Notice] the constructed notice
      def build_from_hash(hash, context: {}, request: nil, user: nil, fingerprint: nil, tags: [])
        notice = Notice.new
        populate_notice_from_hash(notice, hash, fingerprint, tags)
        populate_notice_context(notice, context, request, user)
        notice.environment = Checkend.configuration.environment
        notice
      end

      private

      def populate_notice_from_hash(notice, hash, fingerprint, tags)
        notice.error_class = hash_value(hash, :error_class) || DEFAULT_ERROR_CLASS
        notice.message = truncate_message(hash_value(hash, :message))
        notice.backtrace = clean_backtrace(hash_value(hash, :backtrace) || [])
        notice.fingerprint = fingerprint || hash_value(hash, :fingerprint)
        notice.tags = Array(tags.empty? ? (hash_value(hash, :tags) || []) : tags)
      end

      def populate_notice_context(notice, context, request, user)
        notice.context = merge_context(context)
        notice.user = user || thread_local_user
        notice.request = request || {}
      end

      def hash_value(hash, key)
        hash[key] || hash[key.to_s]
      end

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
        Thread.current[:checkend_user]
      end
    end
  end
end
