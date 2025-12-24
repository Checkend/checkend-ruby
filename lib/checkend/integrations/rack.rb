# frozen_string_literal: true

module Checkend
  module Integrations
    module Rack
      # Rack middleware for capturing unhandled exceptions and request context.
      #
      # @example Basic usage
      #   use Checkend::Integrations::Rack::Middleware
      #
      # @example With Sinatra
      #   class MyApp < Sinatra::Base
      #     use Checkend::Integrations::Rack::Middleware
      #   end
      #
      class Middleware
        # Headers that should be filtered from request data
        FILTERED_HEADERS = %w[
          HTTP_COOKIE
          HTTP_AUTHORIZATION
          HTTP_X_API_KEY
          HTTP_X_AUTH_TOKEN
        ].freeze

        # Headers to exclude entirely (not useful for debugging)
        EXCLUDED_HEADERS = %w[
          HTTP_HOST
          HTTP_CONNECTION
          HTTP_ACCEPT_ENCODING
        ].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          # Store request data for potential error reporting
          request_data = extract_request_data(env)
          Thread.current[:checkend_request] = request_data

          # Set request context
          Checkend.set_context(
            request_id: env['HTTP_X_REQUEST_ID'] || env['action_dispatch.request_id'],
            method: env['REQUEST_METHOD'],
            path: env['PATH_INFO']
          )

          begin
            @app.call(env)
          rescue Exception => e # rubocop:disable Lint/RescueException
            # Report the exception to Checkend
            notify_exception(e, request_data)

            # Re-raise so the error propagates to the app's error handler
            raise
          ensure
            # Clean up thread-local data
            Thread.current[:checkend_request] = nil
            Checkend.clear!
          end
        end

        private

        def notify_exception(exception, request_data)
          return unless Checkend.configuration.valid?

          Checkend.notify(
            exception,
            request: request_data,
            user: Thread.current[:checkend_user]
          )
        rescue StandardError => e
          # Never let SDK errors crash the app
          Checkend.logger.error("[Checkend] Failed to notify: #{e.message}")
        end

        def extract_request_data(env)
          # Guard against Rack not being loaded (defensive)
          return extract_basic_request_data(env) unless defined?(::Rack::Request)

          request = ::Rack::Request.new(env)

          {
            url: request.url,
            method: env['REQUEST_METHOD'],
            path: env['PATH_INFO'],
            query_string: env['QUERY_STRING'],
            params: extract_params(request),
            headers: extract_headers(env),
            remote_ip: extract_remote_ip(env),
            user_agent: env['HTTP_USER_AGENT'],
            referer: env['HTTP_REFERER'],
            content_type: env['CONTENT_TYPE'],
            content_length: env['CONTENT_LENGTH']
          }.compact
        end

        def extract_basic_request_data(env)
          {
            method: env['REQUEST_METHOD'],
            path: env['PATH_INFO'],
            query_string: env['QUERY_STRING'],
            headers: extract_headers(env),
            remote_ip: extract_remote_ip(env),
            user_agent: env['HTTP_USER_AGENT'],
            referer: env['HTTP_REFERER'],
            content_type: env['CONTENT_TYPE'],
            content_length: env['CONTENT_LENGTH']
          }.compact
        end

        def extract_params(request)
          return {} unless Checkend.configuration.send_request_data

          params = {}

          # Query params
          params.merge!(request.GET) if request.GET.any?

          # POST params (only if form data)
          params.merge!(request.POST) if request.POST.any? && form_request?(request)

          sanitize_params(params)
        rescue StandardError
          {}
        end

        def form_request?(request)
          content_type = request.content_type.to_s.downcase
          content_type.include?('form') || content_type.include?('json')
        end

        def extract_headers(env)
          return {} unless Checkend.configuration.send_request_data

          headers = {}

          env.each do |key, value|
            next unless key.start_with?('HTTP_')
            next if EXCLUDED_HEADERS.include?(key)

            header_name = key.sub('HTTP_', '').split('_').map(&:capitalize).join('-')

            headers[header_name] = if FILTERED_HEADERS.include?(key)
                                     '[FILTERED]'
                                   else
                                     value.to_s
                                   end
          end

          headers
        end

        def extract_remote_ip(env)
          # Check common headers for real IP behind proxies
          forwarded = env['HTTP_X_FORWARDED_FOR']
          return forwarded.split(',').first.strip if forwarded

          env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
        end

        def sanitize_params(params)
          filter = Checkend::Filters::SanitizeFilter.new(Checkend.configuration)
          filter.call(params)
        end
      end
    end
  end
end
