# frozen_string_literal: true

require 'test_helper'
require 'rack'
require 'rack/test'
require 'checkend/integrations/rack'

class RackMiddlewareTest < Minitest::Test
  include Rack::Test::Methods
  include CheckendTestHelper

  def app
    @app ||= build_app
  end

  def build_app(inner_app = nil)
    inner = inner_app || ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }
    Rack::Builder.new do
      use Checkend::Integrations::Rack::Middleware
      run inner
    end
  end

  def setup
    super
    @app = nil
  end

  def test_successful_request_passes_through
    configure_checkend

    get '/'

    assert_predicate last_response, :ok?
    assert_equal 'OK', last_response.body
  end

  def test_captures_exception_and_reraises
    configure_checkend
    stub = stub_ingest_api

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/test-path'
    end

    assert_requested stub
  end

  def test_includes_request_data_in_notice
    configure_checkend
    request_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        request_data = JSON.parse(req.body)['request']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/test-path?foo=bar', {}, { 'HTTP_USER_AGENT' => 'TestAgent/1.0' }
    end

    assert_equal 'GET', request_data['method']
    assert_equal '/test-path', request_data['path']
    assert_equal 'foo=bar', request_data['query_string']
    assert_equal 'TestAgent/1.0', request_data['user_agent']
  end

  def test_filters_sensitive_headers
    configure_checkend
    request_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        request_data = JSON.parse(req.body)['request']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/', {}, {
        'HTTP_AUTHORIZATION' => 'Bearer secret-token',
        'HTTP_X_CUSTOM' => 'custom-value'
      }
    end

    assert_equal '[FILTERED]', request_data['headers']['Authorization']
    assert_equal 'custom-value', request_data['headers']['X-Custom']
  end

  def test_filters_sensitive_params
    configure_checkend
    request_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        request_data = JSON.parse(req.body)['request']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/?password=secret123&username=john'
    end

    assert_equal '[FILTERED]', request_data['params']['password']
    assert_equal 'john', request_data['params']['username']
  end

  def test_clears_context_after_request
    configure_checkend
    stub_ingest_api

    # Set some context that should be cleared
    Checkend.set_context(test_key: 'test_value')
    Checkend.set_user(id: 123)

    get '/'

    assert_empty Checkend.context
    assert_nil Checkend.current_user
  end

  def test_clears_context_after_exception
    configure_checkend
    stub_ingest_api

    Checkend.set_context(test_key: 'test_value')

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/'
    end

    assert_empty Checkend.context
  end

  def test_extracts_request_id_from_header
    configure_checkend
    context_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        context_data = JSON.parse(req.body)['context']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/', {}, { 'HTTP_X_REQUEST_ID' => 'req-12345' }
    end

    assert_equal 'req-12345', context_data['request_id']
  end

  def test_extracts_remote_ip_from_forwarded_header
    configure_checkend
    request_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        request_data = JSON.parse(req.body)['request']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/', {}, { 'HTTP_X_FORWARDED_FOR' => '1.2.3.4, 5.6.7.8' }
    end

    assert_equal '1.2.3.4', request_data['remote_ip']
  end

  def test_does_not_send_request_data_when_disabled
    configure_checkend(send_request_data: false)
    request_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        request_data = JSON.parse(req.body)['request']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    assert_raises(StandardError) do
      get '/?username=john', {}, { 'HTTP_X_CUSTOM' => 'value' }
    end

    # Should still have basic request info but not params/headers
    assert_empty request_data['params']
    assert_empty request_data['headers']
  end

  def test_handles_sdk_errors_gracefully
    # Don't configure - SDK not started, so notify will fail gracefully
    # But the original exception should still be raised

    @app = build_app(->(_env) { raise StandardError, 'Test error' })

    # Should raise the original exception, not an SDK error
    error = assert_raises(StandardError) do
      get '/'
    end

    assert_equal 'Test error', error.message
  end

  def test_includes_user_in_notice_when_set
    configure_checkend
    user_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        user_data = JSON.parse(req.body)['user']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @app = build_app(lambda { |_env|
      Checkend.set_user(id: 123, email: 'test@example.com')
      raise StandardError, 'Test error'
    })

    assert_raises(StandardError) do
      get '/'
    end

    assert_equal 123, user_data['id']
    assert_equal 'test@example.com', user_data['email']
  end

  def test_extract_basic_request_data_works_without_rack_request
    configure_checkend
    middleware = Checkend::Integrations::Rack::Middleware.new(nil)

    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/api/test',
      'QUERY_STRING' => 'key=value',
      'HTTP_USER_AGENT' => 'TestAgent',
      'HTTP_REFERER' => 'https://example.com',
      'CONTENT_TYPE' => 'application/json',
      'CONTENT_LENGTH' => '100',
      'REMOTE_ADDR' => '192.168.1.1'
    }

    data = middleware.send(:extract_basic_request_data, env)

    assert_equal 'POST', data[:method]
    assert_equal '/api/test', data[:path]
    assert_equal 'key=value', data[:query_string]
    assert_equal 'TestAgent', data[:user_agent]
    assert_equal 'https://example.com', data[:referer]
    assert_equal 'application/json', data[:content_type]
    assert_equal '100', data[:content_length]
    assert_equal '192.168.1.1', data[:remote_ip]
  end
end
