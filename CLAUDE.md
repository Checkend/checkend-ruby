# CLAUDE.md

This file provides guidance to Claude Code when working with the checkend-ruby SDK.

## Project Overview

checkend-ruby is the official Ruby SDK for Checkend error monitoring. It captures exceptions from Ruby applications and sends them to a Checkend server via the ingestion API.

## Common Commands

```bash
# Run all tests
bundle exec rake test

# Run a specific test file
bundle exec ruby -Ilib:test test/checkend/configuration_test.rb

# Run a specific test method
bundle exec ruby -Ilib:test test/checkend/configuration_test.rb -n test_api_key_from_env

# Run linter
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a

# Build gem locally
gem build checkend-ruby.gemspec

# Install gem locally for testing
gem install checkend-ruby-*.gem
```

## Architecture

### Core Components

- `Checkend` - Main module with public API (notify, configure, set_context, etc.)
- `Configuration` - Holds all configuration options, env var support
- `Client` - HTTP client using Net::HTTP (no dependencies)
- `Notice` - Data structure for error payload
- `NoticeBuilder` - Converts exceptions to Notice objects
- `Worker` - Background thread for async sending
- `Context` - Thread-local context storage
- `Breadcrumbs::Collector` - Ring buffer for breadcrumb storage

### Integrations

- `Integrations::Rack` - Rack middleware for request capture
- `Integrations::Rails` - Rails Railtie for auto-configuration
- `Integrations::Sidekiq` - Sidekiq error handler and middleware
- `Integrations::ActiveJob` - ActiveJob/Solid Queue integration

### Filters

- `Filters::SanitizeFilter` - Scrubs sensitive data (passwords, tokens)
- `Filters::IgnoreFilter` - Checks if exception should be ignored

## Design Principles

1. **Zero Dependencies** - Use only Ruby stdlib (Net::HTTP, JSON, etc.)
2. **Thread Safety** - All shared state uses Mutex or thread-local variables
3. **Non-Blocking** - Default async sending via background thread
4. **Minimal Overhead** - Lazy loading, efficient ring buffer for breadcrumbs
5. **Graceful Degradation** - Never raise exceptions from SDK code

## Target API Contract

The SDK sends to `POST /ingest/v1/errors` with header `Checkend-Ingestion-Key`.

```json
{
  "error": {
    "class": "NoMethodError",
    "message": "undefined method...",
    "backtrace": ["app/models/user.rb:42:in `save'"],
    "fingerprint": "optional-custom-key",
    "tags": ["optional", "tags"]
  },
  "context": {},
  "request": {},
  "user": {},
  "notifier": {
    "name": "checkend-ruby",
    "version": "1.0.0",
    "language": "ruby",
    "language_version": "3.2.0"
  }
}
```

## Testing Strategy

- Use Minitest (not RSpec)
- Use WebMock to stub HTTP requests
- Test each component in isolation
- Integration tests for Rails/Rack/Sidekiq require conditional loading

## Code Style

- Follow rubocop-rails-omakase style guide
- Prefer explicit `require` statements over autoload in gems
- All public methods should have YARD documentation
- Keep files focused and single-responsibility

## Reference: Checkend Server Files

When implementing SDK features, reference these server files:

- `checkend/app/controllers/ingest/v1/errors_controller.rb` - API endpoint
- `checkend/app/controllers/ingest/v1/base_controller.rb` - Auth handling
- `checkend/app/services/error_ingestion_service.rb` - Payload processing
- `checkend/test/controllers/ingest/v1/errors_controller_test.rb` - Expected behavior
