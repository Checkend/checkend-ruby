# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2024-12-24

### Added

- **Core SDK**
  - `Checkend.configure` for SDK configuration
  - `Checkend.notify` for async error reporting
  - `Checkend.notify_sync` for synchronous error reporting
  - `Checkend.set_context` for thread-local context
  - `Checkend.set_user` for user tracking
  - `Checkend.clear!` to reset thread-local data

- **Configuration Options**
  - `api_key` - Required ingestion API key
  - `endpoint` - Required self-hosted Checkend server URL
  - `environment` - Auto-detected from Rails.env or RACK_ENV
  - `enabled` - Enable/disable reporting (default: true in production/staging)
  - `ignored_exceptions` - Exceptions to skip reporting
  - `filter_keys` - Keys to scrub from data (passwords, tokens, etc.)
  - `before_notify` - Callbacks to modify or skip notices
  - `async` - Async sending via background thread (default: true)
  - `max_queue_size` - Maximum notices to queue (default: 1000)
  - `shutdown_timeout` - Seconds to wait on shutdown (default: 5)
  - `timeout` - HTTP request timeout (default: 15s)
  - `open_timeout` - HTTP connection timeout (default: 5s)

- **Background Worker**
  - Thread-safe queue for async sending
  - Graceful shutdown with configurable timeout
  - Automatic drain on process exit

- **Filters**
  - `SanitizeFilter` - Scrubs sensitive keys from hashes
  - `IgnoreFilter` - Filters exceptions by class, name, or pattern

- **Integrations**
  - `Checkend::Integrations::Rack::Middleware` - Rack middleware for exception capture
  - `Checkend::Integrations::Rails::Railtie` - Auto-configuration for Rails apps
  - `Checkend::Integrations::Rails::ControllerMethods` - Controller context tracking
  - `Checkend::Integrations::Sidekiq` - Sidekiq error handler and middleware
  - `Checkend::Integrations::ActiveJob` - ActiveJob/Solid Queue integration

- **Testing**
  - `Checkend::Testing.setup!` - Enable test mode
  - `Checkend::Testing.teardown!` - Restore normal mode
  - `Checkend::Testing.notices` - Access captured notices
  - `Checkend::Testing::FakeClient` - Captures notices instead of sending

### Requirements

- Ruby >= 2.7.0
- No runtime dependencies (uses Ruby stdlib only)

[Unreleased]: https://github.com/Checkend/checkend-ruby/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Checkend/checkend-ruby/releases/tag/v1.0.0
