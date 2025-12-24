# frozen_string_literal: true

require 'logger'

module Checkend
  # Configuration holds all settings for the Checkend SDK.
  #
  # Settings can be configured via environment variables or the configure block:
  #
  #   Checkend.configure do |config|
  #     config.api_key = 'your-ingestion-key'
  #     config.endpoint = 'https://checkend.example.com'
  #   end
  #
  class Configuration
    # Core settings
    attr_accessor :api_key
    attr_accessor :endpoint
    attr_accessor :environment
    attr_accessor :enabled

    # Application metadata
    attr_accessor :app_name
    attr_accessor :revision
    attr_accessor :root_path

    # HTTP settings
    attr_accessor :timeout
    attr_accessor :open_timeout
    attr_accessor :proxy
    attr_accessor :ssl_ca_path
    attr_accessor :ssl_verify

    # Error filtering
    attr_accessor :ignored_exceptions
    attr_accessor :filter_keys
    attr_accessor :before_notify

    # Context settings
    attr_accessor :send_request_data
    attr_accessor :send_session_data
    attr_accessor :send_environment
    attr_accessor :send_user_data

    # Async settings
    attr_accessor :async
    attr_accessor :max_queue_size
    attr_accessor :shutdown_timeout

    # Logging
    attr_accessor :logger
    attr_accessor :debug

    DEFAULT_ENDPOINT = 'https://app.checkend.io'

    DEFAULT_FILTER_KEYS = %w[
      password
      password_confirmation
      passwd
      secret
      token
      api_key
      access_token
      refresh_token
      authorization
      bearer
      credit_card
      card_number
      cvv
      cvc
      ssn
    ].freeze

    DEFAULT_IGNORED_EXCEPTIONS = %w[
      ActiveRecord::RecordNotFound
      ActionController::RoutingError
      ActionController::InvalidAuthenticityToken
      ActionController::UnknownAction
      ActionController::UnknownFormat
      ActionController::UnknownHttpMethod
      ActionDispatch::Http::MimeNegotiation::InvalidType
      CGI::Session::CookieStore::TamperedWithCookie
      Mongoid::Errors::DocumentNotFound
      Sinatra::NotFound
    ].freeze

    def initialize
      @api_key = ENV.fetch('CHECKEND_API_KEY', nil)
      @endpoint = ENV.fetch('CHECKEND_ENDPOINT', DEFAULT_ENDPOINT)
      @environment = detect_environment
      @enabled = nil # Will be computed based on environment
      @timeout = 15
      @open_timeout = 5
      @ssl_verify = true
      @ignored_exceptions = DEFAULT_IGNORED_EXCEPTIONS.dup
      @filter_keys = DEFAULT_FILTER_KEYS.dup
      @before_notify = []
      @send_request_data = true
      @send_session_data = true
      @send_environment = false
      @send_user_data = true
      @async = true
      @max_queue_size = 1000
      @shutdown_timeout = 5
      @debug = ENV.fetch('CHECKEND_DEBUG', 'false') == 'true'
    end

    # Check if configuration is valid for sending errors
    def valid?
      !api_key.nil? && !api_key.empty? && !endpoint.nil? && !endpoint.empty?
    end

    # Check if SDK is enabled (considers explicit setting and environment)
    def enabled?
      return @enabled unless @enabled.nil?

      production_or_staging?
    end

    # Check if an exception should be ignored
    def ignore_exception?(exception)
      exception_class_name = exception.class.name

      ignored_exceptions.any? do |ignored|
        if ignored.is_a?(String)
          exception_class_name == ignored || exception_ancestors_include?(exception, ignored)
        elsif ignored.is_a?(Class)
          exception.is_a?(ignored)
        elsif ignored.is_a?(Regexp)
          ignored.match?(exception_class_name)
        else
          false
        end
      end
    end

    # Get the logger instance
    def resolved_logger
      @logger || default_logger
    end

    private

    def detect_environment
      ENV['CHECKEND_ENVIRONMENT'] ||
        ENV['RAILS_ENV'] ||
        ENV['RACK_ENV'] ||
        'development'
    end

    def production_or_staging?
      %w[production staging].include?(environment)
    end

    def exception_ancestors_include?(exception, class_name)
      exception.class.ancestors.any? { |ancestor| ancestor.name == class_name }
    end

    def default_logger
      @default_logger ||= begin
        logger = Logger.new($stdout)
        logger.level = debug ? Logger::DEBUG : Logger::WARN
        logger.progname = 'Checkend'
        logger
      end
    end
  end
end
