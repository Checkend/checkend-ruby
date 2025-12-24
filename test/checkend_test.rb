# frozen_string_literal: true

require 'test_helper'

class CheckendTest < Minitest::Test
  include CheckendTestHelper

  def test_configure_yields_configuration
    Checkend.configure do |config|
      config.api_key = 'test_key'
    end

    assert_equal 'test_key', Checkend.configuration.api_key
  end

  def test_configure_starts_sdk_when_valid
    configure_checkend

    assert Checkend.instance_variable_get(:@started)
  end

  def test_configure_does_not_start_without_api_key
    Checkend.configure do |config|
      config.endpoint = TEST_ENDPOINT
    end

    refute Checkend.instance_variable_get(:@started)
  end

  def test_notify_sends_error_to_api
    configure_checkend
    stub = stub_ingest_api

    exception = sample_exception
    result = Checkend.notify(exception)

    assert_requested stub
    assert_equal 123, result['id']
  end

  def test_notify_returns_nil_when_not_started
    # Don't configure - SDK not started
    exception = sample_exception
    result = Checkend.notify(exception)

    assert_nil result
  end

  def test_notify_returns_nil_when_disabled
    configure_checkend(enabled: false)
    stub = stub_ingest_api

    exception = sample_exception
    result = Checkend.notify(exception)

    refute_requested stub
    assert_nil result
  end

  def test_notify_skips_ignored_exceptions
    configure_checkend(ignored_exceptions: ['StandardError'])
    stub = stub_ingest_api

    exception = sample_exception
    result = Checkend.notify(exception)

    refute_requested stub
    assert_nil result
  end

  def test_notify_with_context
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['context']['order_id'] == 123 }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = sample_exception
    Checkend.notify(exception, context: { order_id: 123 })

    assert_requested stub
  end

  def test_notify_with_user
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['user']['id'] == 456 }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = sample_exception
    Checkend.notify(exception, user: { id: 456 })

    assert_requested stub
  end

  def test_notify_with_tags
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['error']['tags'] == %w[checkout urgent] }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = sample_exception
    Checkend.notify(exception, tags: %w[checkout urgent])

    assert_requested stub
  end

  def test_notify_with_fingerprint
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['error']['fingerprint'] == 'custom-fp' }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = sample_exception
    Checkend.notify(exception, fingerprint: 'custom-fp')

    assert_requested stub
  end

  def test_before_notify_callback_can_modify_notice
    configure_checkend
    Checkend.configuration.before_notify << lambda { |notice|
      notice.context[:added_by_callback] = true
      true
    }

    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['context']['added_by_callback'] == true }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = sample_exception
    Checkend.notify(exception)

    assert_requested stub
  end

  def test_before_notify_callback_can_cancel_send
    configure_checkend
    Checkend.configuration.before_notify << ->(_notice) { false }
    stub = stub_ingest_api

    exception = sample_exception
    result = Checkend.notify(exception)

    refute_requested stub
    assert_nil result
  end

  def test_notify_sync_sends_synchronously
    configure_checkend
    stub = stub_ingest_api

    exception = sample_exception
    result = Checkend.notify_sync(exception)

    assert_requested stub
    assert_equal 123, result['id']
  end

  def test_set_context
    configure_checkend

    Checkend.set_context(key1: 'value1', key2: 'value2')

    assert_equal 'value1', Checkend.context[:key1]
    assert_equal 'value2', Checkend.context[:key2]
  end

  def test_set_context_merges_with_existing
    configure_checkend
    Checkend.set_context(existing: 'value')

    Checkend.set_context(new_key: 'new_value')

    assert_equal 'value', Checkend.context[:existing]
    assert_equal 'new_value', Checkend.context[:new_key]
  end

  def test_set_user
    configure_checkend

    Checkend.set_user(id: 123, email: 'test@example.com')

    assert_equal 123, Checkend.current_user[:id]
    assert_equal 'test@example.com', Checkend.current_user[:email]
  end

  def test_add_breadcrumb
    configure_checkend

    Checkend.add_breadcrumb('User clicked button', category: 'ui')

    assert_equal 1, Checkend.breadcrumbs.length
    assert_equal 'User clicked button', Checkend.breadcrumbs.first[:message]
    assert_equal 'ui', Checkend.breadcrumbs.first[:category]
  end

  def test_add_breadcrumb_with_metadata
    configure_checkend

    Checkend.add_breadcrumb('API call', category: 'http', metadata: { status: 200 })

    breadcrumb = Checkend.breadcrumbs.first

    assert_equal 200, breadcrumb[:metadata][:status]
  end

  def test_clear_resets_all_thread_local_data
    configure_checkend
    Checkend.set_context(key: 'value')
    Checkend.set_user(id: 123)
    Checkend.add_breadcrumb('test')

    Checkend.clear!

    assert_empty(Checkend.context)
    assert_nil Checkend.current_user
    assert_empty Checkend.breadcrumbs
  end

  def test_stop_resets_started_state
    configure_checkend

    assert Checkend.instance_variable_get(:@started)

    Checkend.stop!

    refute Checkend.instance_variable_get(:@started)
  end

  def test_logger_returns_configuration_logger
    configure_checkend

    assert_instance_of Logger, Checkend.logger
  end
end
