# frozen_string_literal: true

module Checkend
  module Integrations
    module Rails
      # CsrfSubscriber captures CSRF security events from Rails and sends them to Checkend.
      #
      # Rails 8.2+ emits Active Support notifications for CSRF events:
      # - csrf_token_fallback.action_controller - When falling back to token verification
      # - csrf_request_blocked.action_controller - When a request is blocked due to CSRF failure
      # - csrf_javascript_blocked.action_controller - When cross-origin JavaScript is blocked
      #
      # @example Enable CSRF event capture
      #   Checkend.configure do |config|
      #     config.capture_csrf_events = :blocked  # or :all
      #   end
      #
      class CsrfSubscriber
        # Mapping of event names to their severity level
        EVENTS = {
          'csrf_token_fallback.action_controller' => :fallback,
          'csrf_request_blocked.action_controller' => :blocked,
          'csrf_javascript_blocked.action_controller' => :blocked
        }.freeze

        # Synthetic error class names for each event type
        ERROR_CLASSES = {
          'csrf_token_fallback.action_controller' => 'Checkend::Security::CsrfTokenFallback',
          'csrf_request_blocked.action_controller' => 'Checkend::Security::CsrfRequestBlocked',
          'csrf_javascript_blocked.action_controller' => 'Checkend::Security::CsrfJavascriptBlocked'
        }.freeze

        class << self
          # Subscribe to all CSRF events
          #
          # @return [void]
          def subscribe!
            EVENTS.each do |event_name, level|
              ActiveSupport::Notifications.subscribe(event_name) do |*args|
                new.handle_event(event_name, level, args.last)
              end
            end
          end

          # Check if the current Rails version supports CSRF events
          #
          # @return [Boolean] true if Rails 8.2+ is available
          def rails_supports_csrf_events?
            return false unless defined?(::Rails::VERSION::STRING)

            Gem::Version.new(::Rails::VERSION::STRING) >= Gem::Version.new('8.2.0')
          end
        end

        # Handle a CSRF event notification
        #
        # @param event_name [String] the name of the event
        # @param level [Symbol] the severity level (:fallback or :blocked)
        # @param payload [Hash] the event payload from Rails
        # @return [void]
        def handle_event(event_name, level, payload)
          return unless should_capture?(level)

          notice = build_notice(event_name, payload)
          send_notice(notice)
        rescue StandardError => e
          Checkend.logger.debug("[Checkend] Failed to capture CSRF event: #{e.message}")
        end

        private

        # Determine if this event should be captured based on configuration
        #
        # @param level [Symbol] the event severity level
        # @return [Boolean]
        def should_capture?(level)
          setting = Checkend.configuration.capture_csrf_events
          return false unless setting

          return true if setting == :all
          return true if setting.to_sym == :all
          return true if level == :blocked && (setting == :blocked || setting.to_sym == :blocked)

          false
        end

        # Build a Notice object for the CSRF event
        #
        # @param event_name [String] the event name
        # @param payload [Hash] the event payload
        # @return [Notice]
        def build_notice(event_name, payload)
          notice = Notice.new

          # Error info
          notice.error_class = ERROR_CLASSES[event_name]
          notice.message = extract_message(payload)
          notice.backtrace = []
          notice.fingerprint = build_fingerprint(event_name, payload)
          notice.tags = %w[csrf security_event]

          # Context
          notice.context = build_context(payload)

          # Request info
          notice.request = build_request_data(payload)

          # Environment
          notice.environment = Checkend.configuration.environment

          notice
        end

        # Extract the message from the payload
        #
        # @param payload [Hash]
        # @return [String]
        def extract_message(payload)
          payload[:message] || 'CSRF security event'
        end

        # Build a fingerprint for grouping similar events
        #
        # @param event_name [String]
        # @param payload [Hash]
        # @return [String]
        def build_fingerprint(event_name, payload)
          event_type = event_name.split('.').first
          controller = payload[:controller] || 'unknown'
          action = payload[:action] || 'unknown'

          "csrf:#{event_type}:#{controller}:#{action}"
        end

        # Build context data from the payload
        #
        # @param payload [Hash]
        # @return [Hash]
        def build_context(payload)
          ctx = {
            controller: payload[:controller],
            action: payload[:action],
            sec_fetch_site: payload[:sec_fetch_site],
            event_type: 'csrf_security_event'
          }

          # Merge any existing thread-local context
          thread_context = Thread.current[:checkend_context]
          ctx = thread_context.to_h.merge(ctx) if thread_context
          ctx
        end

        # Build request data from the payload
        #
        # @param payload [Hash]
        # @return [Hash]
        def build_request_data(payload)
          return {} unless payload[:request]

          request = payload[:request]
          {
            url: safe_request_url(request),
            method: safe_request_method(request),
            remote_ip: safe_request_ip(request),
            user_agent: safe_request_user_agent(request)
          }.compact
        end

        # Safely extract URL from request
        #
        # @param request [ActionDispatch::Request]
        # @return [String, nil]
        def safe_request_url(request)
          request.original_url
        rescue StandardError
          nil
        end

        # Safely extract HTTP method from request
        #
        # @param request [ActionDispatch::Request]
        # @return [String, nil]
        def safe_request_method(request)
          request.request_method
        rescue StandardError
          nil
        end

        # Safely extract IP from request
        #
        # @param request [ActionDispatch::Request]
        # @return [String, nil]
        def safe_request_ip(request)
          request.remote_ip
        rescue StandardError
          nil
        end

        # Safely extract user agent from request
        #
        # @param request [ActionDispatch::Request]
        # @return [String, nil]
        def safe_request_user_agent(request)
          request.user_agent
        rescue StandardError
          nil
        end

        # Send the notice using the configured method
        #
        # @param notice [Notice]
        # @return [void]
        def send_notice(notice)
          # Run before_notify callbacks
          return unless before_notify_callbacks_allow?(notice)

          if Checkend.configuration.async && Checkend.instance_variable_get(:@worker)
            Checkend.instance_variable_get(:@worker).push(notice)
          else
            client = Checkend.instance_variable_get(:@client) || Client.new(Checkend.configuration)
            client.send_notice(notice)
          end
        end

        # Check if all before_notify callbacks allow sending
        #
        # @param notice [Notice]
        # @return [Boolean]
        def before_notify_callbacks_allow?(notice)
          Checkend.configuration.before_notify.all? do |callback|
            callback.call(notice)
          rescue StandardError => e
            Checkend.logger.debug("[Checkend] before_notify callback failed: #{e.message}")
            true # Continue with other callbacks if one fails
          end
        end
      end
    end
  end
end
