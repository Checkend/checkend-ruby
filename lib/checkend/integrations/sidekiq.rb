# frozen_string_literal: true

module Checkend
  module Integrations
    # Sidekiq integration for capturing job errors.
    #
    # @example Installation
    #   # config/initializers/checkend.rb
    #   require 'checkend/integrations/sidekiq'
    #   Checkend::Integrations::Sidekiq.install!
    #
    module Sidekiq
      class << self
        # Install the Sidekiq error handler and middleware
        #
        # @return [void]
        def install!
          return unless sidekiq_available?

          install_error_handler
          install_server_middleware
        end

        # Check if Sidekiq is available
        #
        # @return [Boolean]
        def sidekiq_available?
          defined?(::Sidekiq)
        end

        private

        def install_error_handler
          ::Sidekiq.configure_server do |config|
            config.error_handlers << ErrorHandler.new
          end
        end

        def install_server_middleware
          ::Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.add ServerMiddleware
            end
          end
        end
      end

      # Error handler that reports exceptions to Checkend
      class ErrorHandler
        def call(exception, context)
          return unless Checkend.configuration.valid?

          job_context = extract_job_context(context)

          Checkend.notify(
            exception,
            context: job_context,
            tags: ['sidekiq']
          )
        rescue StandardError => e
          Checkend.logger.error("[Checkend] Failed to notify Sidekiq error: #{e.message}")
        end

        private

        def extract_job_context(context)
          return {} unless context.is_a?(Hash)

          job = context[:job] || {}

          {
            sidekiq: {
              queue: job['queue'],
              class: job['class'],
              jid: job['jid'],
              retry_count: job['retry_count'] || 0,
              args: sanitize_args(job['args'])
            }
          }
        end

        def sanitize_args(args)
          return [] if args.nil?

          filter = Checkend::Filters::SanitizeFilter.new(Checkend.configuration)
          filter.call(args)
        rescue StandardError
          ['[ARGS HIDDEN]']
        end
      end

      # Server middleware that sets context for each job
      class ServerMiddleware
        def call(_worker, job, queue)
          set_job_context(job, queue)
          yield
        ensure
          Checkend.clear!
        end

        private

        def set_job_context(job, queue)
          Checkend.set_context(
            sidekiq: {
              queue: queue,
              class: job['class'],
              jid: job['jid'],
              retry_count: job['retry_count'] || 0
            }
          )
        end
      end
    end
  end
end
