# frozen_string_literal: true

require_relative 'lib/checkend/version'

Gem::Specification.new do |spec|
  spec.name          = 'checkend-ruby'
  spec.version       = Checkend::VERSION
  spec.authors       = ['Simon Chiu']
  spec.email         = ['checkend@furvur.com']

  spec.summary       = 'Ruby SDK for Checkend error monitoring'
  spec.description   = 'Capture and report errors from Ruby applications to Checkend. ' \
                       'Includes automatic integrations for Rails, Rack, Sidekiq, and Solid Queue.'
  spec.homepage      = 'https://github.com/furvur/checkend-ruby'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/furvur/checkend-ruby'
  spec.metadata['changelog_uri'] = 'https://github.com/furvur/checkend-ruby/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['{lib}/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md'].reject { |f| File.directory?(f) }
  end

  spec.require_paths = ['lib']

  # Ruby stdlib gems that are being extracted (future-proofing for Ruby 3.5+)
  spec.add_dependency 'json'
  spec.add_dependency 'logger'
  spec.add_dependency 'uri'
end
