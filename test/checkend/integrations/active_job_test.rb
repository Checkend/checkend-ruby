# frozen_string_literal: true

require 'test_helper'
require 'checkend/integrations/active_job'

class ActiveJobIntegrationTest < Minitest::Test
  include CheckendTestHelper

  def test_active_job_module_exists
    assert defined?(Checkend::Integrations::ActiveJob)
  end

  def test_extension_module_exists
    assert defined?(Checkend::Integrations::ActiveJob::Extension)
  end

  def test_active_job_available_returns_false_without_activejob
    refute_predicate Checkend::Integrations::ActiveJob, :active_job_available?
  end

  def test_skip_adapters_includes_sidekiq
    assert_includes Checkend::Integrations::ActiveJob::SKIP_ADAPTERS, 'sidekiq'
  end

  def test_skip_adapters_includes_resque
    assert_includes Checkend::Integrations::ActiveJob::SKIP_ADAPTERS, 'resque'
  end
end

# Test the extension methods in isolation
class ActiveJobExtensionTest < Minitest::Test
  include CheckendTestHelper

  # Mock job class to test extension methods
  class MockJob
    # Define stub methods BEFORE including the module
    def self.around_perform(_method)
      # Stub for testing
    end

    def self.rescue_from(_exception, &_block)
      # Stub for testing
    end

    def self.class_eval(&block)
      # Execute the block to define methods, but stub callbacks
      instance_eval(&block)
    end

    def self.queue_adapter
      SolidQueueAdapter.new
    end

    def self.try(_method)
      nil
    end

    def self.name
      'MockJob'
    end

    include Checkend::Integrations::ActiveJob::Extension

    attr_accessor :job_id, :queue_name, :executions, :priority, :arguments

    def initialize
      @job_id = 'job-123'
      @queue_name = 'default'
      @executions = 1
      @priority = nil
      @arguments = []
    end
  end

  # Simulates ActiveJob::QueueAdapters::SolidQueueAdapter
  # Empty class is intentional - only the class name is used
  class SolidQueueAdapter; end # rubocop:disable Lint/EmptyClass

  def setup
    super
    @job = MockJob.new
  end

  def test_checkend_set_job_context
    configure_checkend

    @job.send(:checkend_set_job_context)

    context = Checkend.context[:active_job]

    assert_equal 'MockJob', context[:job_class]
    assert_equal 'job-123', context[:job_id]
    assert_equal 'default', context[:queue_name]
    assert_equal 1, context[:executions]
  end

  def test_checkend_sanitize_arguments
    configure_checkend
    @job.arguments = [{ password: 'secret', user_id: 1 }]

    sanitized = @job.send(:checkend_sanitize_arguments)

    assert_equal '[FILTERED]', sanitized[0][:password]
    assert_equal 1, sanitized[0][:user_id]
  end

  def test_checkend_sanitize_arguments_with_empty_args
    configure_checkend
    @job.arguments = []

    sanitized = @job.send(:checkend_sanitize_arguments)

    assert_empty sanitized
  end

  def test_checkend_sanitize_arguments_with_nil_args
    configure_checkend
    @job.arguments = nil

    sanitized = @job.send(:checkend_sanitize_arguments)

    assert_empty sanitized
  end

  def test_checkend_skip_adapter_returns_true_for_sidekiq
    configure_checkend

    # Create a mock that returns sidekiq adapter
    job = MockJob.new
    def job.queue_adapter_name
      'sidekiq'
    end

    assert job.send(:checkend_skip_adapter?)
  end

  def test_checkend_skip_adapter_returns_false_for_solid_queue
    configure_checkend

    # queue_adapter_name should extract 'solid_queue' from the adapter class name
    refute @job.send(:checkend_skip_adapter?)
  end

  def test_checkend_should_report_returns_true_on_first_execution
    configure_checkend
    @job.executions = 1

    exception = StandardError.new('Test error')

    assert @job.send(:checkend_should_report?, exception)
  end

  def test_checkend_notify_error_sends_to_api # rubocop:disable Metrics/AbcSize
    configure_checkend
    error_data = nil
    context_data = nil

    stub_request(:post, "#{TEST_ENDPOINT}/ingest/v1/errors")
      .with do |req|
        body = JSON.parse(req.body)
        error_data = body['error']
        context_data = body['context']
        true
      end
      .to_return(status: 201, body: { id: 1, problem_id: 1 }.to_json)

    @job.arguments = [123, 'test']
    exception = StandardError.new('Job failed')

    @job.send(:checkend_notify_error, exception)

    assert_includes error_data['tags'], 'active_job'
    assert_includes error_data['tags'], 'default'
    assert_equal 'MockJob', context_data['active_job']['job_class']
    assert_equal 'job-123', context_data['active_job']['job_id']
    assert_equal [123, 'test'], context_data['active_job']['arguments']
  end

  def test_checkend_notify_error_does_not_crash_on_sdk_error
    # Don't configure - will cause SDK issues
    exception = StandardError.new('Job failed')

    # Should not raise
    @job.send(:checkend_notify_error, exception)
  end

  def test_checkend_reraise_raises_exception
    exception = StandardError.new('Test error')

    assert_raises(StandardError) do
      @job.send(:checkend_reraise, exception)
    end
  end

  def test_checkend_around_perform_clears_context
    configure_checkend
    Checkend.set_context(existing: 'value')

    @job.send(:checkend_around_perform) do
      # Job execution
    end

    assert_empty Checkend.context
  end

  def test_checkend_around_perform_clears_context_on_error
    configure_checkend
    Checkend.set_context(existing: 'value')

    assert_raises(RuntimeError) do
      @job.send(:checkend_around_perform) do
        raise 'Job error'
      end
    end

    assert_empty Checkend.context
  end
end
