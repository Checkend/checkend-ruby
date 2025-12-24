# frozen_string_literal: true

require_relative 'rack'

module Checkend
  module Integrations
    module Rails
      # Controller methods for Rails integration
      # This module can be included in controllers to add Checkend context tracking
      module ControllerMethods
        def self.included(base)
          base.class_eval do
            before_action :checkend_set_request_context
            after_action :checkend_clear_context
          end
        end

        private

        # Set request context for error tracking
        def checkend_set_request_context
          Checkend.set_context(
            controller: controller_name,
            action: action_name,
            request_id: request.request_id
          )

          # Capture current user if available
          if respond_to?(:current_user, true) && (user = current_user)
            Checkend.set_user(extract_user_info(user))
          end
        rescue StandardError => e
          # Never let SDK errors break the app
          Checkend.logger.debug("[Checkend] Failed to set context: #{e.message}")
        end

        # Clear context after request completes
        def checkend_clear_context
          Checkend.clear!
        rescue StandardError => e
          Checkend.logger.debug("[Checkend] Failed to clear context: #{e.message}")
        end

        # Extract user information from a user object
        #
        # @param user [Object] the user object
        # @return [Hash] user info hash
        def extract_user_info(user)
          info = {}

          # Try common user attributes
          info[:id] = user.id if user.respond_to?(:id)
          info[:email] = user.email if user.respond_to?(:email)
          info[:name] = extract_user_name(user)

          info.compact
        end

        # Try various methods to get user name
        def extract_user_name(user)
          %i[name full_name display_name username].each do |method|
            return user.public_send(method) if user.respond_to?(method)
          end
          nil
        end
      end
    end
  end
end

# Only define the Railtie if Rails is available
if defined?(Rails::Railtie)
  module Checkend
    module Integrations
      module Rails
        # Rails Railtie for automatic Checkend configuration.
        #
        # This railtie:
        # - Sets up default configuration from Rails settings
        # - Inserts Rack middleware for exception capturing
        # - Adds controller helpers for context tracking
        #
        # @example Basic usage (config/initializers/checkend.rb)
        #   Checkend.configure do |config|
        #     config.api_key = ::Rails.application.credentials.checkend[:api_key]
        #   end
        #
        class Railtie < ::Rails::Railtie
          initializer 'checkend.configure' do |_app|
            # Set Rails-specific defaults before user configuration
            Checkend.configuration.tap do |config|
              config.root_path = ::Rails.root.to_s
              config.environment = ::Rails.env.to_s
              config.logger = ::Rails.logger
            end
          end

          initializer 'checkend.middleware' do |app|
            # Insert after DebugExceptions so we catch errors that aren't rescued
            app.middleware.insert_after(
              ActionDispatch::DebugExceptions,
              Checkend::Integrations::Rack::Middleware
            )
          end

          initializer 'checkend.action_controller' do
            ActiveSupport.on_load(:action_controller) do
              include Checkend::Integrations::Rails::ControllerMethods
            end
          end
        end
      end
    end
  end
end
