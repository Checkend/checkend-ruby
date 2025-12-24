# frozen_string_literal: true

require 'json'
require 'time'

module Checkend
  # Notice represents an error payload to be sent to Checkend.
  #
  # This class is typically created by NoticeBuilder from an exception,
  # but can also be constructed manually for custom error reporting.
  #
  class Notice
    # Error information
    attr_accessor :error_class
    attr_accessor :message
    attr_accessor :backtrace
    attr_accessor :fingerprint
    attr_accessor :tags

    # Context information
    attr_accessor :context
    attr_accessor :request
    attr_accessor :user

    # Breadcrumbs
    attr_accessor :breadcrumbs

    # Metadata
    attr_accessor :environment
    attr_accessor :occurred_at

    def initialize
      @backtrace = []
      @tags = []
      @context = {}
      @request = {}
      @user = {}
      @breadcrumbs = []
      @occurred_at = Time.now.utc.iso8601
    end

    # Convert the notice to a JSON string
    #
    # @return [String] JSON representation
    def to_json(*_args)
      to_h.to_json
    end

    # Convert the notice to a hash
    #
    # @return [Hash] hash representation
    def to_h
      {
        error: error_payload,
        context: context_with_environment,
        request: request || {},
        user: user || {},
        breadcrumbs: breadcrumbs || [],
        notifier: notifier_payload
      }.compact
    end

    private

    def error_payload
      payload = {
        class: error_class,
        message: message,
        backtrace: backtrace || []
      }
      payload[:fingerprint] = fingerprint if fingerprint
      payload[:tags] = tags if tags && !tags.empty?
      payload
    end

    def context_with_environment
      ctx = context || {}
      ctx = ctx.merge(environment: environment) if environment
      ctx
    end

    def notifier_payload
      {
        name: 'checkend-ruby',
        version: VERSION,
        language: 'ruby',
        language_version: RUBY_VERSION
      }
    end
  end
end
