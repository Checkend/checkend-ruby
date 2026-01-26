# frozen_string_literal: true

require_relative 'checkend/version'
require_relative 'checkend/configuration'
require_relative 'checkend/notice'
require_relative 'checkend/notice_builder'
require_relative 'checkend/client'
require_relative 'checkend/worker'
require_relative 'checkend/filters/sanitize_filter'
require_relative 'checkend/filters/ignore_filter'

# Checkend is the main module for the Checkend Ruby SDK.
#
# Use Checkend.configure to set up the SDK, then Checkend.notify to report errors.
#
# @example Basic configuration
#   Checkend.configure do |config|
#     config.api_key = 'your-ingestion-key'
#   end
#
# @example Reporting an error
#   begin
#     # risky code
#   rescue => e
#     Checkend.notify(e)
#   end
#
module Checkend
  class << self
    # Get the current configuration
    #
    # @return [Configuration] the configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure the Checkend SDK
    #
    # @yield [Configuration] the configuration instance
    # @return [Configuration] the configuration instance
    def configure
      yield(configuration) if block_given?
      start! if configuration.valid?
      configuration
    end

    # Start the SDK (initialize client, worker, etc.)
    #
    # Called automatically after configure if configuration is valid.
    def start!
      return if @started

      @started = true
      @client = Client.new(configuration)
      @worker = Worker.new(configuration) if configuration.async
      install_at_exit_hook
      log_info("Started (environment: #{configuration.environment}, async: #{configuration.async})")
    end

    # Stop the SDK and clean up resources
    #
    # @param timeout [Integer] seconds to wait for pending notices
    def stop!(timeout: nil)
      @worker&.shutdown(timeout: timeout)
      @worker = nil
      @started = false
      @client = nil
      log_info('Stopped')
    end

    # Flush pending notices, blocking until sent
    #
    # @param timeout [Integer] seconds to wait
    def flush(timeout: nil)
      @worker&.flush(timeout: timeout)
    end

    # ========== Primary API ==========

    # Report an error or custom notification to Checkend
    #
    # Accepts an Exception, String message, or Hash with error details.
    #
    # @param exception_or_message [Exception, String, Hash] the error to report
    #   - Exception: reports the exception with its class, message, and backtrace
    #   - String: reports a custom notification with the string as the message
    #   - Hash: reports a custom notification with :error_class, :message, :backtrace
    # @param error_class [String] custom error class (only used with String messages)
    # @param context [Hash] additional context data
    # @param request [Hash] request information
    # @param user [Hash] user information
    # @param fingerprint [String] custom fingerprint for grouping
    # @param tags [Array<String>] tags for filtering
    # @return [Hash, nil] the API response or nil if not sent
    #
    # @example Report an exception
    #   Checkend.notify(exception)
    #
    # @example Report a custom message
    #   Checkend.notify("User exceeded rate limit", error_class: "RateLimitExceeded")
    #
    # @example Report with a hash
    #   Checkend.notify(error_class: "CustomAlert", message: "Something happened")
    #
    def notify(exception_or_message, error_class: nil, context: {}, request: nil, user: nil, fingerprint: nil, tags: [])
      return nil unless should_notify?

      notice = build_notice(
        exception_or_message,
        error_class: error_class,
        context: context,
        request: request,
        user: user,
        fingerprint: fingerprint,
        tags: tags
      )
      return nil unless notice

      # Run before_notify callbacks
      return nil unless before_notify_callbacks_allow?(notice)

      send_notice(notice)
    end

    # Report an error or custom notification synchronously (blocking)
    #
    # Useful for CLI tools, tests, or when you need confirmation of delivery.
    #
    # @param exception_or_message [Exception, String, Hash] the error to report
    # @param options [Hash] same options as notify
    # @return [Hash, nil] the API response or nil if not sent
    def notify_sync(exception_or_message, **options)
      return nil unless should_notify?

      notice = build_notice(exception_or_message, **options)
      return nil unless notice

      client.send_notice(notice)
    end

    # ========== Context Management ==========

    # Get the current thread-local context
    #
    # @return [Hash] the context hash
    def context
      Thread.current[:checkend_context] ||= {}
    end

    # Set context data for the current thread
    #
    # @param hash [Hash] context data to merge
    def set_context(hash)
      Thread.current[:checkend_context] ||= {}
      Thread.current[:checkend_context].merge!(hash)
    end

    # Set user information for the current thread
    #
    # @param user_hash [Hash] user data (id, email, name, etc.)
    def set_user(user_hash)
      Thread.current[:checkend_user] = user_hash
    end

    # Get the current user
    #
    # @return [Hash, nil] the user hash
    def current_user
      Thread.current[:checkend_user]
    end

    # Clear all thread-local context
    def clear!
      Thread.current[:checkend_context] = nil
      Thread.current[:checkend_user] = nil
    end

    # Reset all SDK state (useful for testing)
    #
    # @return [void]
    def reset!
      stop!(timeout: 0) if @started
      @configuration = nil
      @client = nil
      @worker = nil
      @started = false
      @at_exit_installed = nil
      clear!
    end

    # ========== Logging Helpers ==========

    # Get the logger
    #
    # @return [Logger] the logger instance
    def logger
      configuration.resolved_logger
    end

    private

    def should_notify?
      return false unless @started
      return false unless configuration.valid?
      return false unless configuration.enabled?

      true
    end

    def build_notice(exception_or_message, error_class: nil, context: {}, request: nil, user: nil,
                     fingerprint: nil, tags: [])
      options = { context: context, request: request, user: user, fingerprint: fingerprint, tags: tags }

      case exception_or_message
      when Exception
        return nil if configuration.ignore_exception?(exception_or_message)

        NoticeBuilder.build(exception: exception_or_message, **options)
      when String
        NoticeBuilder.build_from_message(exception_or_message, error_class: error_class, **options)
      when Hash
        NoticeBuilder.build_from_hash(exception_or_message, **options)
      else
        log_debug("notify called with unsupported type: #{exception_or_message.class}")
        nil
      end
    end

    def before_notify_callbacks_allow?(notice)
      configuration.before_notify.each do |callback|
        result = callback.call(notice)
        return false unless result
      rescue StandardError => e
        log_debug("before_notify callback failed: #{e.message}")
        # Continue with other callbacks
      end
      true
    end

    def send_notice(notice)
      if configuration.async && @worker
        @worker.push(notice)
        nil # Async doesn't return result
      else
        client.send_notice(notice)
      end
    end

    def client
      @client ||= Client.new(configuration)
    end

    def install_at_exit_hook
      return if @at_exit_installed

      @at_exit_installed = true
      at_exit { stop! }
    end

    def log_info(message)
      logger.info("[Checkend] #{message}")
    end

    def log_debug(message)
      logger.debug("[Checkend] #{message}")
    end
  end
end
