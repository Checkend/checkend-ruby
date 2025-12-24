# frozen_string_literal: true

require 'test_helper'
require 'checkend/integrations/sidekiq'

class SidekiqIntegrationTest < Minitest::Test
  include CheckendTestHelper

  def test_sidekiq_module_exists
    assert defined?(Checkend::Integrations::Sidekiq)
  end

  def test_error_handler_class_exists
    assert defined?(Checkend::Integrations::Sidekiq::ErrorHandler)
  end

  def test_server_middleware_class_exists
    assert defined?(Checkend::Integrations::Sidekiq::ServerMiddleware)
  end

  def test_sidekiq_available_returns_false_without_sidekiq
    refute_predicate Checkend::Integrations::Sidekiq, :sidekiq_available?
  end
end

class SidekiqErrorHandlerTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    @handler = Checkend::Integrations::Sidekiq::ErrorHandler.new
  end

  def test_reports_exception_with_job_context
    configure_checkend
    context_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        context_data = JSON.parse(req.body)['context']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = StandardError.new('Job failed')
    job_context = {
      job: {
        'queue' => 'default',
        'class' => 'MyWorker',
        'jid' => 'abc123',
        'retry_count' => 2,
        'args' => [1, 'test']
      }
    }

    @handler.call(exception, job_context)

    assert_equal 'default', context_data['sidekiq']['queue']
    assert_equal 'MyWorker', context_data['sidekiq']['class']
    assert_equal 'abc123', context_data['sidekiq']['jid']
    assert_equal 2, context_data['sidekiq']['retry_count']
  end

  def test_includes_sidekiq_tag
    configure_checkend
    error_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        error_data = JSON.parse(req.body)['error']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = StandardError.new('Job failed')
    @handler.call(exception, { job: {} })

    assert_includes error_data['tags'], 'sidekiq'
  end

  def test_sanitizes_sensitive_args
    configure_checkend
    context_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        context_data = JSON.parse(req.body)['context']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = StandardError.new('Job failed')
    job_context = {
      job: {
        'queue' => 'default',
        'class' => 'MyWorker',
        'jid' => 'abc123',
        'args' => [{ 'password' => 'secret123', 'user_id' => 1 }]
      }
    }

    @handler.call(exception, job_context)

    args = context_data['sidekiq']['args']

    assert_equal '[FILTERED]', args[0]['password']
    assert_equal 1, args[0]['user_id']
  end

  def test_handles_nil_context_gracefully
    configure_checkend
    stub = stub_ingest_api

    exception = StandardError.new('Job failed')
    @handler.call(exception, nil)

    assert_requested stub
  end

  def test_handles_empty_job_context
    configure_checkend
    context_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        context_data = JSON.parse(req.body)['context']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    exception = StandardError.new('Job failed')
    @handler.call(exception, {})

    # Should have sidekiq context with nil values
    assert context_data.key?('sidekiq')
  end

  def test_does_not_crash_on_sdk_error
    # Don't configure - will cause SDK error
    exception = StandardError.new('Job failed')

    # Should not raise
    @handler.call(exception, { job: {} })
  end
end

class SidekiqServerMiddlewareTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    @middleware = Checkend::Integrations::Sidekiq::ServerMiddleware.new
  end

  def test_sets_context_before_job
    configure_checkend
    context_set = nil

    job = {
      'class' => 'TestWorker',
      'jid' => 'xyz789',
      'retry_count' => 0
    }

    @middleware.call(nil, job, 'default') do
      context_set = Checkend.context.dup
    end

    assert_equal 'default', context_set[:sidekiq][:queue]
    assert_equal 'TestWorker', context_set[:sidekiq][:class]
    assert_equal 'xyz789', context_set[:sidekiq][:jid]
  end

  def test_clears_context_after_job
    configure_checkend
    Checkend.set_context(existing: 'value')

    job = { 'class' => 'TestWorker', 'jid' => 'xyz789' }

    @middleware.call(nil, job, 'default') do
      # Job execution
    end

    assert_empty Checkend.context
  end

  def test_clears_context_even_on_error
    configure_checkend
    Checkend.set_context(existing: 'value')

    job = { 'class' => 'TestWorker', 'jid' => 'xyz789' }

    assert_raises(RuntimeError) do
      @middleware.call(nil, job, 'default') do
        raise 'Job error'
      end
    end

    assert_empty Checkend.context
  end

  def test_yields_to_block
    configure_checkend
    block_called = false

    job = { 'class' => 'TestWorker', 'jid' => 'xyz789' }

    @middleware.call(nil, job, 'default') do
      block_called = true
    end

    assert block_called
  end
end
