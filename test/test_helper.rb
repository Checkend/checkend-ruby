# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'checkend'
require 'minitest/autorun'
require 'webmock/minitest'

# Disable real HTTP connections in tests
WebMock.disable_net_connect!

module CheckendTestHelper
  VALID_API_KEY = 'test_ingestion_key_12345'
  TEST_ENDPOINT = 'https://test.checkend.io'

  def setup
    # Reset Checkend state before each test
    Checkend.reset!
  end

  def configure_checkend(api_key: VALID_API_KEY, endpoint: TEST_ENDPOINT, async: false, **options)
    Checkend.configure do |config|
      config.api_key = api_key
      config.endpoint = endpoint
      config.environment = 'test'
      config.enabled = true
      config.async = async # Disable async by default in tests
      options.each { |key, value| config.send("#{key}=", value) }
    end
  end

  def stub_ingest_api(status: 201, body: { id: 123, problem_id: 456 })
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_return(
        status: status,
        body: body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def sample_exception
    raise StandardError, 'Test error message'
  rescue StandardError => e
    e
  end

  def sample_exception_with_backtrace
    raise_nested_error
  rescue StandardError => e
    e
  end

  def raise_nested_error
    inner_method
  end

  def inner_method
    raise 'Nested error'
  end
end
