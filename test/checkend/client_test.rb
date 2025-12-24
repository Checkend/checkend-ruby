# frozen_string_literal: true

require 'test_helper'

class ClientTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.environment = 'test'
  end

  def test_send_notice_success
    stub = stub_ingest_api(status: 201, body: { id: 123, problem_id: 456 })

    client = Checkend::Client.new(@config)
    notice = build_test_notice

    result = client.send_notice(notice)

    assert_requested stub
    assert_equal 123, result['id']
    assert_equal 456, result['problem_id']
  end

  def test_send_notice_includes_correct_headers
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with(
             headers: {
               'Content-Type' => 'application/json',
               'Checkend-Ingestion-Key' => VALID_API_KEY
             }
           )
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    client = Checkend::Client.new(@config)
    client.send_notice(build_test_notice)

    assert_requested stub
  end

  def test_send_notice_includes_user_agent
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with(
             headers: {
               'User-Agent' => %r{^checkend-ruby/\d+\.\d+\.\d+ Ruby/\d+\.\d+\.\d+}
             }
           )
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    client = Checkend::Client.new(@config)
    client.send_notice(build_test_notice)

    assert_requested stub
  end

  def test_send_notice_unauthorized
    stub_ingest_api(status: 401, body: { error: 'Invalid ingestion key' })

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_unprocessable_entity
    stub_ingest_api(status: 422, body: { error: 'error.class is required' })

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_rate_limited
    stub_ingest_api(status: 429, body: { error: 'Rate limited' })

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_server_error
    stub_ingest_api(status: 500, body: { error: 'Internal server error' })

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_bad_request
    stub_ingest_api(status: 400, body: { error: 'Malformed JSON' })

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_network_error
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_timeout

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_send_notice_connection_refused
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_raise(Errno::ECONNREFUSED)

    client = Checkend::Client.new(@config)
    result = client.send_notice(build_test_notice)

    assert_nil result
  end

  def test_sends_json_payload
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |request| JSON.parse(request.body)['error']['class'] == 'TestError' }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    client = Checkend::Client.new(@config)
    notice = build_test_notice
    notice.error_class = 'TestError'
    client.send_notice(notice)

    assert_requested stub
  end

  private

  def build_test_notice
    notice = Checkend::Notice.new
    notice.error_class = 'StandardError'
    notice.message = 'Test error'
    notice.backtrace = ['test.rb:1:in `test`']
    notice
  end
end
