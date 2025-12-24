# Checkend Ruby

[![Gem Version](https://badge.fury.io/rb/checkend-ruby.svg)](https://badge.fury.io/rb/checkend-ruby)
[![CI](https://github.com/furvur/checkend-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/furvur/checkend-ruby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Official Ruby SDK for [Checkend](https://github.com/furvur/checkend) error monitoring. Capture and report errors from Ruby applications with automatic Rails, Rack, Sidekiq, and Solid Queue integrations.

## Installation

Add to your Gemfile:

```ruby
gem 'checkend-ruby'
```

Then run:

```bash
bundle install
```

## Quick Start

### Rails

Add an initializer at `config/initializers/checkend.rb`:

```ruby
Checkend.configure do |config|
  config.api_key = Rails.application.credentials.checkend[:api_key]
  # Or use environment variable: ENV['CHECKEND_API_KEY']
end
```

That's it! The gem automatically:
- Installs Rack middleware to capture unhandled exceptions
- Tracks request context (URL, params, headers)
- Captures current user info if `current_user` is available

### Rack / Sinatra

```ruby
require 'checkend-ruby'

Checkend.configure do |config|
  config.api_key = ENV['CHECKEND_API_KEY']
  config.endpoint = 'https://checkend.example.com'
end

use Checkend::Integrations::Rack::Middleware
```

### Manual Error Reporting

```ruby
begin
  # risky code
rescue => e
  Checkend.notify(e)
  raise
end

# With additional context
Checkend.notify(exception,
  context: { order_id: 123 },
  user: { id: current_user.id, email: current_user.email },
  tags: ['checkout', 'payment']
)
```

## Configuration

```ruby
Checkend.configure do |config|
  # Required
  config.api_key = 'your-ingestion-key'

  # Optional - Checkend server URL (default: https://app.checkend.io)
  config.endpoint = 'https://checkend.example.com'

  # Optional - Environment name (auto-detected from Rails.env or RACK_ENV)
  config.environment = 'production'

  # Optional - Enable/disable reporting (default: true in production/staging)
  config.enabled = Rails.env.production?

  # Optional - Exceptions to ignore
  config.ignored_exceptions += ['MyCustomNotFoundError']

  # Optional - Keys to filter from params/context
  config.filter_keys += ['credit_card', 'ssn']

  # Optional - Custom callback before sending
  config.before_notify << ->(notice) {
    notice.context[:deploy_version] = ENV['DEPLOY_VERSION']
    true  # Return true to send, false to skip
  }

  # Optional - Async sending (default: true)
  config.async = true
end
```

## Context and User Tracking

Set context that will be included with all errors:

```ruby
# In a controller before_action
Checkend.set_context(
  account_id: current_account.id,
  feature_flag: 'new_checkout'
)

# Track current user
Checkend.set_user(
  id: current_user.id,
  email: current_user.email,
  name: current_user.full_name
)
```

## Sidekiq Integration

Errors in Sidekiq jobs are automatically captured:

```ruby
# config/initializers/checkend.rb
require 'checkend/integrations/sidekiq'
Checkend::Integrations::Sidekiq.install!
```

## ActiveJob / Solid Queue Integration

ActiveJob errors are automatically captured after the retry threshold:

```ruby
# Automatically included via Rails Railtie
# No additional configuration needed
```

## Testing

Disable error reporting in tests:

```ruby
# test/test_helper.rb
Checkend::Testing.setup!

# In your tests
def test_captures_error
  begin
    raise StandardError, 'Test error'
  rescue => e
    Checkend.notify(e)
  end

  assert_equal 1, Checkend::Testing.notices.size
  assert_equal 'StandardError', Checkend::Testing.last_notice.error_class
end
```

## Requirements

- Ruby >= 2.7.0
- No runtime dependencies (uses Ruby stdlib only)

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run linter
bundle exec rubocop
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a Pull Request
