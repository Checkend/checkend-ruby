# frozen_string_literal: true

module Checkend
  module Integrations
    # ActiveJob integration for capturing job errors.
    #
    # Works with any ActiveJob backend including Solid Queue, Sidekiq, etc.
    # For Sidekiq, the Sidekiq integration is preferred as it provides
    # more detailed context.
    #
    # @example Manual installation
    #   # config/initializers/checkend.rb
    #   require 'checkend/integrations/active_job'
    #   Checkend::Integrations::ActiveJob.install!
    #
    # @example With Rails (automatic via Railtie)
    #   # No additional configuration needed
    #
    module ActiveJob
      # Adapters that have their own error handling (use those instead)
      SKIP_ADAPTERS = %w[
        sidekiq
        resque
      ].freeze

      class << self
        # Install the ActiveJob extension
        #
        # @return [void]
        def install!
          return unless active_job_available?

          ::ActiveJob::Base.include(Extension)
        end

        # Check if ActiveJob is available
        #
        # @return [Boolean]
        def active_job_available?
          defined?(::ActiveJob::Base)
        end
      end

      # Extension module to include in ActiveJob::Base
      module Extension
        extend ActiveSupport::Concern if defined?(ActiveSupport::Concern)

        def self.included(base)
          base.class_eval do
            around_perform :checkend_around_perform
            rescue_from(StandardError) { |e| checkend_handle_error(e) }
          end
        end

        private

        def checkend_around_perform
          checkend_set_job_context
          yield
        ensure
          Checkend.clear!
        end

        def checkend_set_job_context
          Checkend.set_context(
            active_job: {
              job_class: self.class.name,
              job_id: job_id,
              queue_name: queue_name,
              executions: executions,
              priority: priority
            }
          )
        end

        def checkend_handle_error(exception)
          # Skip if adapter handles errors itself
          return checkend_reraise(exception) if checkend_skip_adapter?

          # Only report after retry threshold to avoid duplicate reports
          checkend_notify_error(exception) if checkend_should_report?(exception)

          checkend_reraise(exception)
        end

        def checkend_skip_adapter?
          adapter_name = queue_adapter_name
          SKIP_ADAPTERS.include?(adapter_name)
        end

        def queue_adapter_name
          # Get the adapter class name and extract the adapter type
          # e.g., "ActiveJob::QueueAdapters::SidekiqAdapter" -> "sidekiq"
          adapter_class = self.class.queue_adapter.class.name
          # Handle module paths: get last part
          name = adapter_class.split('::').last
          # Convert to snake_case and remove _adapter suffix
          name.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '').sub(/_adapter$/, '')
        rescue StandardError
          'unknown'
        end

        def checkend_should_report?(exception)
          # Report on first execution or if we've exceeded retry count
          return true if executions >= checkend_retry_threshold

          # Also report if this is an unhandled exception type
          !checkend_retryable_exception?(exception)
        end

        def checkend_retry_threshold
          # Default: report after 1 execution (immediate report)
          # Can be overridden in job class
          respond_to?(:checkend_report_after_retries) ? checkend_report_after_retries : 1
        end

        def checkend_retryable_exception?(exception)
          # Check if job has retry_on for this exception
          retry_exceptions = self.class.try(:retry_on_exceptions) || []
          retry_exceptions.any? { |ex| exception.is_a?(ex) }
        rescue StandardError
          false
        end

        def checkend_notify_error(exception)
          return unless Checkend.configuration.valid?

          Checkend.notify(
            exception,
            context: {
              active_job: {
                job_class: self.class.name,
                job_id: job_id,
                queue_name: queue_name,
                executions: executions,
                priority: priority,
                arguments: checkend_sanitize_arguments
              }
            },
            tags: ['active_job', queue_name].compact
          )
        rescue StandardError => e
          Checkend.logger.error("[Checkend] Failed to notify ActiveJob error: #{e.message}")
        end

        def checkend_sanitize_arguments
          return [] if arguments.nil? || arguments.empty?

          filter = Checkend::Filters::SanitizeFilter.new(Checkend.configuration)
          filter.call(arguments)
        rescue StandardError
          ['[ARGS HIDDEN]']
        end

        def checkend_reraise(exception)
          raise exception
        end
      end
    end
  end
end
