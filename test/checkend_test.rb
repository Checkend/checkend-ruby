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
      config.api_key = nil # Explicitly clear (env var may be set)
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

  def test_set_user_includes_user_in_notice_payload
    configure_checkend
    Checkend.set_user(id: 456, email: 'user@example.com')

    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['user']['id'] == 456 }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify(sample_exception)

    assert_requested stub
  end

  def test_clear_resets_all_thread_local_data
    configure_checkend
    Checkend.set_context(key: 'value')
    Checkend.set_user(id: 123)

    Checkend.clear!

    assert_empty(Checkend.context)
    assert_nil Checkend.current_user
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

  def test_reset_clears_all_state
    configure_checkend
    Checkend.set_context(key: 'value')
    Checkend.set_user(id: 123)

    Checkend.reset!

    refute Checkend.instance_variable_get(:@started)
    assert_nil Checkend.instance_variable_get(:@configuration)
    assert_nil Checkend.instance_variable_get(:@client)
    assert_empty Checkend.context
    assert_nil Checkend.current_user
  end

  def test_before_notify_callback_exception_does_not_prevent_send
    configure_checkend

    # First callback raises, second should still run
    Checkend.configuration.before_notify << ->(_notice) { raise 'Callback error!' }
    Checkend.configuration.before_notify << lambda { |notice|
      notice.context[:second_callback_ran] = true
      true
    }

    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with { |req| JSON.parse(req.body)['context']['second_callback_ran'] == true }
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify(sample_exception)

    assert_requested stub
  end

  # ========== Custom Notification Tests (String/Hash) ==========

  def test_notify_with_string_message
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'Checkend::Notice' &&
               body['error']['message'] == 'Something went wrong' &&
               body['error']['backtrace'] == []
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify('Something went wrong')

    assert_requested stub
  end

  def test_notify_with_string_and_custom_error_class
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'RateLimitExceeded' &&
               body['error']['message'] == 'User exceeded rate limit'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify('User exceeded rate limit', error_class: 'RateLimitExceeded')

    assert_requested stub
  end

  def test_notify_with_string_and_context
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['message'] == 'Custom alert' &&
               body['context']['severity'] == 'high'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify('Custom alert', context: { severity: 'high' })

    assert_requested stub
  end

  def test_notify_with_hash
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'DataValidationError' &&
               body['error']['message'] == 'Invalid email format'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify({ error_class: 'DataValidationError', message: 'Invalid email format' })

    assert_requested stub
  end

  def test_notify_with_hash_and_backtrace
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'CustomError' &&
               body['error']['backtrace'].first.include?('custom_file.rb')
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify(
      {
        error_class: 'CustomError',
        message: 'Something happened',
        backtrace: ['custom_file.rb:10:in `method`']
      }
    )

    assert_requested stub
  end

  def test_notify_with_hash_defaults_error_class
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'Checkend::Notice'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify({ message: 'Just a message' })

    assert_requested stub
  end

  def test_notify_sync_with_string
    configure_checkend
    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['error']['class'] == 'SyncNotification' &&
               body['error']['message'] == 'Sync message'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    result = Checkend.notify_sync('Sync message', error_class: 'SyncNotification')

    assert_requested stub
    assert_equal 1, result['id']
  end

  def test_notify_with_string_includes_thread_local_context
    configure_checkend
    Checkend.set_context(tenant_id: 'abc123')

    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['context']['tenant_id'] == 'abc123'
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify('Custom notification')

    assert_requested stub
  end

  def test_notify_with_string_includes_thread_local_user
    configure_checkend
    Checkend.set_user(id: 789, email: 'user@example.com')

    stub = stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
           .with do |req|
             body = JSON.parse(req.body)
             body['user']['id'] == 789
           end
           .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    Checkend.notify('Custom notification')

    assert_requested stub
  end

  def test_notify_returns_nil_for_unsupported_type
    configure_checkend

    result = Checkend.notify(12_345)

    assert_nil result
  end
end
