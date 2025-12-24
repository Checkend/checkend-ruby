# frozen_string_literal: true

require 'test_helper'

# Advanced scenario tests covering:
# - Thread safety stress tests
# - Real-world timeout scenarios
# - Multiple before_notify callbacks
# - Proxy configuration
class AdvancedScenariosTest < Minitest::Test
  include CheckendTestHelper

  def teardown
    Checkend.stop! if Checkend.instance_variable_get(:@started)
    super
  end

  # ========== Thread Safety Stress Tests ==========

  def test_concurrent_notify_calls_are_thread_safe
    configure_checkend
    stub = stub_ingest_api

    threads = 20.times.map do |i|
      Thread.new do
        5.times do |j|
          raise StandardError, "Error #{i}-#{j}"
        rescue StandardError => e
          Checkend.notify(e, context: { thread: i, iteration: j })
        end
      end
    end

    threads.each(&:join)

    # All 100 notices should have been attempted
    assert_requested stub, times: 100
  end

  def test_concurrent_context_setting_is_isolated
    configure_checkend
    stub_ingest_api

    results = Queue.new
    threads = spawn_context_threads(10, results)
    threads.each(&:join)

    verify_thread_isolation(results)
  end

  def test_concurrent_worker_pushes_under_load
    configure_checkend(async: true, max_queue_size: 1000)
    stub_ingest_api

    worker = Checkend.instance_variable_get(:@worker)

    threads = 10.times.map do
      Thread.new do
        50.times do
          notice = Checkend::Notice.new
          notice.error_class = 'LoadTest'
          notice.message = "Thread #{Thread.current.object_id}"
          worker.push(notice)
        end
      end
    end

    threads.each(&:join)

    # Flush and verify
    Checkend.flush(timeout: 5)
    Checkend.stop!(timeout: 2)

    # Worker should have processed notices without crashing
    refute_predicate worker, :running?
  end

  def test_rapid_configure_reconfigure_cycles
    stub_ingest_api

    10.times do |i|
      Checkend.instance_variable_set(:@configuration, nil)
      Checkend.instance_variable_set(:@client, nil)
      Checkend.instance_variable_set(:@worker, nil)
      Checkend.instance_variable_set(:@started, false)

      configure_checkend(api_key: "key_#{i}")

      exception = sample_exception
      Checkend.notify(exception)

      Checkend.stop!(timeout: 1)
    end

    # If we got here without deadlock or crash, test passes
    assert true
  end

  # ========== Real-world Timeout Scenarios ==========

  def test_slow_server_response_times_out
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.timeout = 1
    @config.open_timeout = 1

    # Simulate very slow response
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_timeout

    client = Checkend::Client.new(@config)
    notice = build_test_notice

    start_time = Time.now
    result = client.send_notice(notice)
    elapsed = Time.now - start_time

    assert_nil result
    # Should timeout reasonably quickly, not hang forever
    assert_operator elapsed, :<, 10, "Request took too long: #{elapsed}s"
  end

  def test_connection_timeout_is_respected
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.open_timeout = 1
    @config.timeout = 1

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_raise(Net::OpenTimeout.new('connection timed out'))

    client = Checkend::Client.new(@config)
    notice = build_test_notice

    start_time = Time.now
    result = client.send_notice(notice)
    elapsed = Time.now - start_time

    assert_nil result
    assert_operator elapsed, :<, 5, "Connection attempt took too long: #{elapsed}s"
  end

  def test_worker_handles_sustained_timeouts
    configure_checkend(async: true, shutdown_timeout: 2)

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_timeout

    worker = Checkend.instance_variable_get(:@worker)

    # Push several notices that will all timeout
    5.times do
      notice = Checkend::Notice.new
      notice.error_class = 'TimeoutTest'
      notice.message = 'This will timeout'
      worker.push(notice)
    end

    # Worker should handle timeouts gracefully and shutdown
    Checkend.stop!(timeout: 5)

    refute_predicate worker, :running?
  end

  def test_flush_respects_timeout_parameter
    configure_checkend(async: true)

    # Block the queue with slow responses
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_return do
        sleep 0.5
        { status: 201, body: { id: 1, problem_id: 1 }.to_json }
      end

    worker = Checkend.instance_variable_get(:@worker)
    10.times { worker.push(build_test_notice) }

    start_time = Time.now
    Checkend.flush(timeout: 1)
    elapsed = Time.now - start_time

    # Flush should return around timeout, not wait forever
    assert_operator elapsed, :<, 3, "Flush took too long: #{elapsed}s"
  end

  # ========== Multiple before_notify Callbacks ==========

  def test_multiple_callbacks_execute_in_order
    configure_checkend
    execution_order = []

    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :first
      true
    }
    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :second
      true
    }
    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :third
      true
    }

    stub_ingest_api
    Checkend.notify(sample_exception)

    assert_equal %i[first second third], execution_order
  end

  def test_callback_chain_stops_on_first_false
    configure_checkend
    execution_order = []

    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :first
      true
    }
    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :second
      false # This should stop the chain
    }
    Checkend.configuration.before_notify << lambda { |_notice|
      execution_order << :third # Should not execute
      true
    }

    stub = stub_ingest_api
    result = Checkend.notify(sample_exception)

    assert_equal %i[first second], execution_order
    refute_requested stub
    assert_nil result
  end

  def test_callbacks_can_chain_context_modifications
    configure_checkend
    setup_chained_callbacks

    stub = stub_chained_context_request
    Checkend.notify(sample_exception)

    assert_requested stub
  end

  def test_callback_exception_does_not_crash_notify
    configure_checkend

    Checkend.configuration.before_notify << ->(_notice) { raise 'Callback exploded!' }

    stub = stub_ingest_api

    # Callback exception is caught, notice is still sent
    result = Checkend.notify(sample_exception)

    assert_requested stub
    assert_equal 123, result['id']
  end

  def test_callback_with_nil_return_treated_as_falsy
    configure_checkend

    Checkend.configuration.before_notify << ->(_notice) {}

    stub = stub_ingest_api
    result = Checkend.notify(sample_exception)

    refute_requested stub
    assert_nil result
  end

  def test_many_callbacks_performance
    configure_checkend
    call_count = 0

    # Add 100 callbacks
    100.times do |i|
      Checkend.configuration.before_notify << lambda { |notice|
        call_count += 1
        notice.context["callback_#{i}"] = true
        true
      }
    end

    stub_ingest_api

    start_time = Time.now
    Checkend.notify(sample_exception)
    elapsed = Time.now - start_time

    assert_equal 100, call_count
    assert_operator elapsed, :<, 1, "100 callbacks took too long: #{elapsed}s"
  end

  # ========== Proxy Configuration ==========

  def test_client_respects_proxy_setting
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.proxy = 'http://proxy.example.com:8080'

    Checkend::Client.new(@config)

    # We can't easily test actual proxy usage with WebMock,
    # but we can verify the config is read
    assert_equal 'http://proxy.example.com:8080', @config.proxy
  end

  def test_proxy_with_authentication
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.proxy = 'http://user:password@proxy.example.com:8080'

    # Verify URI parsing works correctly
    proxy_uri = URI.parse(@config.proxy)

    assert_equal 'proxy.example.com', proxy_uri.host
    assert_equal 8080, proxy_uri.port
    assert_equal 'user', proxy_uri.user
    assert_equal 'password', proxy_uri.password
  end

  def test_ssl_verification_can_be_disabled
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.ssl_verify = false

    refute @config.ssl_verify
  end

  def test_custom_ssl_ca_path
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.ssl_ca_path = '/etc/ssl/certs/custom-ca.pem'

    assert_equal '/etc/ssl/certs/custom-ca.pem', @config.ssl_ca_path
  end

  private

  def build_test_notice
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.message = 'Test message'
    notice.backtrace = ['test.rb:1:in `test`']
    notice
  end

  def spawn_context_threads(count, results)
    count.times.map do |i|
      Thread.new { run_context_thread(i, results) }
    end
  end

  def run_context_thread(thread_num, results)
    Checkend.set_context(thread_id: thread_num)
    Checkend.set_user(id: thread_num, email: "user#{thread_num}@example.com")
    sleep(rand * 0.01)

    results << {
      thread: thread_num,
      context_thread_id: Checkend.context[:thread_id],
      user_id: Checkend.current_user[:id]
    }
    Checkend.clear!
  end

  def verify_thread_isolation(results)
    results.size.times do
      result = results.pop

      assert_equal result[:thread], result[:context_thread_id],
                   "Thread #{result[:thread]} had wrong context"
      assert_equal result[:thread], result[:user_id],
                   "Thread #{result[:thread]} had wrong user_id"
    end
  end

  def setup_chained_callbacks
    Checkend.configuration.before_notify << lambda { |notice|
      notice.context[:step1] = 'done'
      true
    }
    Checkend.configuration.before_notify << lambda { |notice|
      notice.context[:step2] = notice.context[:step1] ? 'after_step1' : 'no_step1'
      true
    }
    Checkend.configuration.before_notify << lambda { |notice|
      notice.context[:final] = "#{notice.context[:step1]}_#{notice.context[:step2]}"
      true
    }
  end

  def stub_chained_context_request
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with { |req| chained_context_valid?(req) }
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)
  end

  def chained_context_valid?(req)
    body = JSON.parse(req.body)
    body['context']['step1'] == 'done' &&
      body['context']['step2'] == 'after_step1' &&
      body['context']['final'] == 'done_after_step1'
  end
end
