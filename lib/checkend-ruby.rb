# frozen_string_literal: true

require_relative 'checkend'

# Detect and load framework integrations
if defined?(Rails::Railtie)
  require_relative 'checkend/integrations/rails'
elsif defined?(Sidekiq)
  require_relative 'checkend/integrations/sidekiq'
end
