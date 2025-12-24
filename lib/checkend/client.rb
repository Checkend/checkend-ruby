# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module Checkend
  # HTTP client for sending error notices to the Checkend API.
  #
  # Uses Net::HTTP from Ruby stdlib with no external dependencies.
  #
  class Client
    INGEST_PATH = '/ingest/v1/errors'
    USER_AGENT = "checkend-ruby/#{VERSION} Ruby/#{RUBY_VERSION}"

    def initialize(config)
      @config = config
      @uri = URI.parse("#{config.endpoint}#{INGEST_PATH}")
    end

    # Send a notice to the Checkend API
    #
    # @param notice [Notice] the notice to send
    # @return [Hash, nil] the response body on success, nil on failure
    def send_notice(notice)
      response = post(notice.to_json)
      handle_response(response)
    rescue StandardError => e
      log_error("Failed to send notice: #{e.class} - #{e.message}")
      nil
    end

    private

    def post(body)
      http = build_http
      request = build_request(body)
      http.request(request)
    end

    def build_http
      http = if @config.proxy
               proxy_uri = URI.parse(@config.proxy)
               Net::HTTP.new(@uri.host, @uri.port, proxy_uri.host, proxy_uri.port,
                             proxy_uri.user, proxy_uri.password)
             else
               Net::HTTP.new(@uri.host, @uri.port)
             end

      http.use_ssl = @uri.scheme == 'https'
      http.verify_mode = @config.ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.ca_file = @config.ssl_ca_path if @config.ssl_ca_path
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.timeout

      http
    end

    def build_request(body)
      request = Net::HTTP::Post.new(@uri.path)
      request['Content-Type'] = 'application/json'
      request['Checkend-Ingestion-Key'] = @config.api_key
      request['User-Agent'] = USER_AGENT
      request.body = body
      request
    end

    def handle_response(response)
      case response.code.to_i
      when 201
        result = JSON.parse(response.body)
        log_debug("Notice sent successfully: id=#{result['id']} problem_id=#{result['problem_id']}")
        result
      when 400
        log_warn("Bad request: #{response.body}")
        nil
      when 401
        log_error('Authentication failed - check your API key')
        nil
      when 422
        log_warn("Invalid notice payload: #{response.body}")
        nil
      when 429
        log_warn('Rate limited by server - backing off')
        nil
      when 500..599
        log_error("Server error: #{response.code} - #{response.body}")
        nil
      else
        log_error("Unexpected response: #{response.code} - #{response.body}")
        nil
      end
    end

    def log_debug(message)
      @config.resolved_logger.debug("[Checkend] #{message}")
    end

    def log_warn(message)
      @config.resolved_logger.warn("[Checkend] #{message}")
    end

    def log_error(message)
      @config.resolved_logger.error("[Checkend] #{message}")
    end
  end
end
