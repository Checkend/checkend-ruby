# Checkend Ruby

[![Gem Version](https://badge.fury.io/rb/checkend-ruby.svg)](https://badge.fury.io/rb/checkend-ruby)
[![CI](https://github.com/Checkend/checkend-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/Checkend/checkend-ruby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Official Ruby SDK for [Checkend](https://github.com/Checkend/checkend) error monitoring. Capture and report errors from Ruby applications with automatic Rails, Rack, Sidekiq, and Solid Queue integrations.

## Features

- **Zero dependencies** - Uses only Ruby stdlib (Net::HTTP, JSON)
- **Async sending** - Non-blocking error reporting via background thread
- **Automatic context** - Captures request, user, and environment data
- **Sensitive data filtering** - Automatically scrubs passwords, tokens, etc.
- **Framework integrations** - Rails, Rack, Sidekiq, ActiveJob/Solid Queue

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
  config.endpoint = 'https://your-checkend-server.com'  # Your self-hosted Checkend URL
end
```

That's it! The gem automatically:
- Installs Rack middleware to capture unhandled exceptions
- Tracks request context (URL, params, headers)
- Captures current user info if `current_user` is available

### Rack / Sinatra

```ruby
require 'checkend-ruby'
require 'checkend/integrations/rack'

Checkend.configure do |config|
  config.api_key = ENV['CHECKEND_API_KEY']
  config.endpoint = 'https://your-checkend-server.com'
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
  tags: ['checkout', 'payment'],
  fingerprint: 'custom-grouping-key'
)

# Synchronous sending (blocks until sent)
Checkend.notify_sync(exception)
```

## Configuration

```ruby
Checkend.configure do |config|
  # Required
  config.api_key = 'your-ingestion-key'

  # Required - Your self-hosted Checkend server URL
  config.endpoint = 'https://your-checkend-server.com'

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
  config.max_queue_size = 1000      # Max notices to queue
  config.shutdown_timeout = 5       # Seconds to wait on shutdown

  # Optional - HTTP settings
  config.timeout = 15               # Request timeout in seconds
  config.open_timeout = 5           # Connection timeout in seconds
end
```

### Environment Variables

The SDK respects these environment variables:

| Variable | Description |
|----------|-------------|
| `CHECKEND_API_KEY` | Your ingestion API key |
| `CHECKEND_ENDPOINT` | Custom server endpoint |
| `CHECKEND_ENVIRONMENT` | Override environment name |
| `CHECKEND_DEBUG` | Enable debug logging (`true`/`false`) |

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

# Clear context (automatically done after each request in Rails)
Checkend.clear!
```

## Integrations

### Sidekiq

Errors in Sidekiq jobs are automatically captured:

```ruby
# config/initializers/checkend.rb
require 'checkend/integrations/sidekiq'
Checkend::Integrations::Sidekiq.install!
```

Job context (queue, class, jid, retry_count) is automatically included.

### ActiveJob / Solid Queue

For ActiveJob with backends other than Sidekiq/Resque:

```ruby
# config/initializers/checkend.rb
require 'checkend/integrations/active_job'
Checkend::Integrations::ActiveJob.install!
```

Note: If using Sidekiq as your ActiveJob backend, use the Sidekiq integration instead for better context.

## Testing

Use the Testing module to capture notices without sending them:

```ruby
require 'checkend/testing'

# In your test setup
Checkend::Testing.setup!

# In your test teardown
Checkend::Testing.teardown!
```

### Minitest Example

```ruby
class MyTest < Minitest::Test
  def setup
    Checkend::Testing.setup!
  end

  def teardown
    Checkend::Testing.teardown!
  end

  def test_error_is_reported
    begin
      raise StandardError, 'Test error'
    rescue => e
      Checkend.notify(e)
    end

    assert_equal 1, Checkend::Testing.notice_count
    assert_equal 'StandardError', Checkend::Testing.last_notice.error_class
    assert_equal 'Test error', Checkend::Testing.last_notice.message
  end
end
```

### RSpec Example

```ruby
RSpec.configure do |config|
  config.before(:each) do
    Checkend::Testing.setup!
  end

  config.after(:each) do
    Checkend::Testing.teardown!
  end
end

RSpec.describe MyService do
  it 'reports errors' do
    expect { MyService.call }.to raise_error(StandardError)

    expect(Checkend::Testing.notices?).to be true
    expect(Checkend::Testing.last_notice.error_class).to eq('StandardError')
  end
end
```

### Testing API

| Method | Description |
|--------|-------------|
| `Checkend::Testing.setup!` | Enable test mode, capture notices |
| `Checkend::Testing.teardown!` | Restore normal mode, clear notices |
| `Checkend::Testing.notices` | Array of captured Notice objects |
| `Checkend::Testing.last_notice` | Most recent notice |
| `Checkend::Testing.first_notice` | First captured notice |
| `Checkend::Testing.notice_count` | Number of captured notices |
| `Checkend::Testing.notices?` | True if any notices captured |
| `Checkend::Testing.clear_notices!` | Clear captured notices |

## Filtering Sensitive Data

The SDK automatically filters sensitive data from:
- Request parameters
- Request headers
- Context data
- Job arguments

Default filtered keys: `password`, `secret`, `token`, `api_key`, `authorization`, `credit_card`, `cvv`, `ssn`

Add custom keys:

```ruby
Checkend.configure do |config|
  config.filter_keys += ['social_security_number', 'bank_account']
end
```

## Ignoring Exceptions

Some exceptions don't need to be reported:

```ruby
Checkend.configure do |config|
  # By class name (string)
  config.ignored_exceptions += ['MyNotFoundError']

  # By class
  config.ignored_exceptions += [ActiveRecord::RecordNotFound]

  # By pattern
  config.ignored_exceptions += [/NotFound$/]
end
```

Default ignored exceptions include `ActiveRecord::RecordNotFound`, `ActionController::RoutingError`, and other common "expected" errors.

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

# Build gem locally
gem build checkend-ruby.gemspec
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a Pull Request
