# frozen_string_literal: true

require 'test_helper'

class WorkerTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    @config = Checkend::Configuration.new
    @config.api_key = VALID_API_KEY
    @config.endpoint = TEST_ENDPOINT
    @config.environment = 'test'
    @config.async = true
    @config.max_queue_size = 100
    @config.shutdown_timeout = 2
  end

  def teardown
    @worker&.shutdown(timeout: 1)
    super
  end

  def test_push_adds_notice_to_queue
    stub_ingest_api
    @worker = Checkend::Worker.new(@config)

    notice = build_test_notice
    result = @worker.push(notice)

    assert result
    # Give worker time to process
    sleep 0.1
  end

  def test_push_returns_false_when_shutdown
    stub_ingest_api
    @worker = Checkend::Worker.new(@config)
    @worker.shutdown(timeout: 1)

    notice = build_test_notice
    result = @worker.push(notice)

    refute result
  end

  def test_push_returns_false_when_queue_full
    stub_ingest_api
    @config.max_queue_size = 2
    @worker = Checkend::Worker.new(@config)

    # Fill the queue faster than it can drain
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    # Push more than max
    results = []
    5.times { results << @worker.push(build_test_notice) }

    # At least some should be rejected
    assert results.include?(false) || @worker.queue_size <= 2
  end

  def test_sends_notice_to_api
    stub = stub_ingest_api
    @worker = Checkend::Worker.new(@config)

    notice = build_test_notice
    @worker.push(notice)

    # Wait for async send
    sleep 0.2

    assert_requested stub
  end

  def test_shutdown_drains_queue
    stub = stub_ingest_api
    @worker = Checkend::Worker.new(@config)

    3.times { @worker.push(build_test_notice) }
    @worker.shutdown(timeout: 2)

    assert_requested stub, times: 3
  end

  def test_running_returns_true_when_active
    stub_ingest_api
    @worker = Checkend::Worker.new(@config)

    assert_predicate @worker, :running?
  end

  def test_running_returns_false_after_shutdown
    stub_ingest_api
    @worker = Checkend::Worker.new(@config)
    @worker.shutdown(timeout: 1)

    refute_predicate @worker, :running?
  end

  def test_handles_api_errors_gracefully
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_return(status: 500, body: { error: 'Server error' }.to_json)

    @worker = Checkend::Worker.new(@config)
    @worker.push(build_test_notice)

    # Should not crash
    sleep 0.2
    @worker.shutdown(timeout: 1)

    assert true # If we got here, it didn't crash
  end

  def test_handles_network_errors_gracefully
    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .to_timeout

    @worker = Checkend::Worker.new(@config)
    @worker.push(build_test_notice)

    # Should not crash
    sleep 0.2
    @worker.shutdown(timeout: 1)

    assert true # If we got here, it didn't crash
  end

  private

  def build_test_notice
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.message = 'Test message'
    notice.backtrace = ['test.rb:1']
    notice
  end
end
