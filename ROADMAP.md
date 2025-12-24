# checkend-ruby Roadmap

## Version 1.0 - Full SDK Release

### Phase 1: Core Foundation

- [ ] **Gem Structure Setup**
  - [ ] Create gemspec with metadata (name, version, authors, license)
  - [ ] Create Gemfile with dev dependencies (minitest, webmock, rubocop, rake)
  - [ ] Create Rakefile with test task
  - [ ] Create lib/checkend-ruby.rb entry point
  - [ ] Create lib/checkend.rb main module
  - [ ] Create lib/checkend/version.rb

- [ ] **Configuration Class** (`lib/checkend/configuration.rb`)
  - [ ] Core settings: api_key, endpoint, environment, enabled
  - [ ] HTTP settings: timeout, open_timeout, ssl_verify
  - [ ] Environment variable support (CHECKEND_API_KEY, CHECKEND_ENDPOINT)
  - [ ] Auto-detect environment from Rails.env / RACK_ENV
  - [ ] Default values for all settings

- [ ] **HTTP Client** (`lib/checkend/client.rb`)
  - [ ] POST to /ingest/v1/errors using Net::HTTP
  - [ ] Set Checkend-Ingestion-Key header
  - [ ] Set Content-Type and User-Agent headers
  - [ ] Handle response codes (201, 401, 422, 429, 5xx)
  - [ ] Timeout handling
  - [ ] SSL/TLS support

- [ ] **Notice Data Structure** (`lib/checkend/notice.rb`)
  - [ ] Error payload (class, message, backtrace, fingerprint, tags)
  - [ ] Context, request, user hashes
  - [ ] Notifier info (name, version, language, language_version)
  - [ ] to_json serialization

- [ ] **Notice Builder** (`lib/checkend/notice_builder.rb`)
  - [ ] Convert exception to Notice
  - [ ] Clean backtrace paths (remove project root prefix)
  - [ ] Limit backtrace to 100 lines
  - [ ] Merge thread-local context

- [ ] **Main Module API** (`lib/checkend.rb`)
  - [ ] Checkend.configure block DSL
  - [ ] Checkend.notify(exception, context:, user:, tags:)
  - [ ] Checkend.notify_sync(exception) for blocking send
  - [ ] Checkend.configuration accessor

- [ ] **Unit Tests**
  - [ ] test/checkend/configuration_test.rb
  - [ ] test/checkend/client_test.rb
  - [ ] test/checkend/notice_test.rb
  - [ ] test/checkend/notice_builder_test.rb

### Phase 2: Background Sending & Filtering

- [ ] **Background Worker** (`lib/checkend/worker.rb`)
  - [ ] Thread with queue for async sending
  - [ ] Queue.new for thread-safe push/pop
  - [ ] Max queue size (default: 1000)
  - [ ] Graceful shutdown with timeout
  - [ ] Throttling on errors (exponential backoff)
  - [ ] at_exit callback to drain queue

- [ ] **Sanitize Filter** (`lib/checkend/filters/sanitize_filter.rb`)
  - [ ] Recursive hash/array traversal
  - [ ] Match keys against filter_keys patterns
  - [ ] Replace values with "[FILTERED]"
  - [ ] Truncate long strings (10,000 chars)
  - [ ] Handle circular references

- [ ] **Ignore Filter** (`lib/checkend/filters/ignore_filter.rb`)
  - [ ] Check exception class against ignored_exceptions
  - [ ] Support class name strings and patterns
  - [ ] Default ignores: RecordNotFound, RoutingError, InvalidAuthenticityToken

- [ ] **Before Notify Callbacks**
  - [ ] Array of procs in configuration
  - [ ] Pass Notice to each callback
  - [ ] Skip sending if callback returns false
  - [ ] Modify notice in place

- [ ] **Unit Tests**
  - [ ] test/checkend/worker_test.rb
  - [ ] test/checkend/filters/sanitize_filter_test.rb
  - [ ] test/checkend/filters/ignore_filter_test.rb

### Phase 3: Integrations

- [ ] **Rack Middleware** (`lib/checkend/integrations/rack.rb`)
  - [ ] Checkend::Integrations::Rack::Middleware class
  - [ ] Rescue exceptions and call Checkend.notify
  - [ ] Re-raise after notifying
  - [ ] Capture request info (url, method, params, headers, ip)
  - [ ] Filter sensitive headers (Cookie, Authorization)
  - [ ] Clear context on request end

- [ ] **Rails Railtie** (`lib/checkend/integrations/rails.rb`)
  - [ ] Checkend::Integrations::Rails < Rails::Railtie
  - [ ] Set root_path, environment, logger from Rails
  - [ ] Insert middleware after ActionDispatch::DebugExceptions
  - [ ] Include controller methods via ActiveSupport.on_load

- [ ] **Rails Controller Methods**
  - [ ] before_action to set context (controller, action, request_id)
  - [ ] Capture current_user if available
  - [ ] after_action to clear context
  - [ ] Store request hash for error reporting

- [ ] **Sidekiq Integration** (`lib/checkend/integrations/sidekiq.rb`)
  - [ ] Checkend::Integrations::Sidekiq::ErrorHandler
  - [ ] Checkend::Integrations::Sidekiq::ServerMiddleware
  - [ ] Checkend::Integrations::Sidekiq.install! class method
  - [ ] Capture job context (queue, class, jid, retry_count)
  - [ ] Sanitize job arguments

- [ ] **ActiveJob Integration** (`lib/checkend/integrations/active_job.rb`)
  - [ ] Checkend::Integrations::ActiveJob::Extension module
  - [ ] around_perform callback
  - [ ] Set job context (class, id, queue, executions)
  - [ ] Only report after retry threshold (default: 1)
  - [ ] Skip if adapter handles errors (Sidekiq, Resque)

- [ ] **Integration Tests**
  - [ ] test/checkend/integrations/rack_test.rb
  - [ ] test/checkend/integrations/rails_test.rb (conditional)
  - [ ] test/checkend/integrations/sidekiq_test.rb (conditional)
  - [ ] test/checkend/integrations/active_job_test.rb (conditional)

### Phase 4: Testing & Release

- [ ] **Testing Module** (`lib/checkend/testing.rb`)
  - [ ] Checkend::Testing.setup! disables async, stubs client
  - [ ] Checkend::Testing.teardown! restores original state
  - [ ] Checkend::Testing.notices returns captured notices
  - [ ] Checkend::Testing.last_notice helper
  - [ ] Checkend::Testing.clear_notices! helper
  - [ ] FakeClient class that captures instead of sending

- [ ] **Documentation**
  - [ ] Complete README with all features
  - [ ] YARD documentation for public methods
  - [ ] CHANGELOG.md with 1.0.0 entry
  - [ ] LICENSE file (MIT)

- [ ] **CI/CD Setup**
  - [ ] .github/workflows/ci.yml
  - [ ] Test matrix: Ruby 2.7, 3.0, 3.1, 3.2, 3.3
  - [ ] Run rubocop
  - [ ] Upload coverage

- [ ] **Release Preparation**
  - [ ] Verify all tests pass
  - [ ] Run security audit (bundle-audit)
  - [ ] Test against Checkend server locally
  - [ ] Tag v1.0.0
  - [ ] Publish to RubyGems

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Repository | Separate repo | Better for gem publishing, independent versioning |
| Ruby version | >= 2.7 | Broader compatibility |
| Dependencies | Zero (stdlib only) | Like Honeybadger - no version conflicts |
| HTTP client | Net::HTTP | Part of stdlib, no dependencies |
| Async sending | Background thread + Mutex/Queue | Non-blocking, stdlib only |
| Context storage | Thread-local variables | Safe for concurrent requests |
| Rails integration | Railtie | Auto-configuration on boot |
| Testing | Minitest | Matches Checkend server conventions |

---

## Files to Create

```
checkend-ruby/
├── lib/
│   ├── checkend-ruby.rb
│   ├── checkend.rb
│   └── checkend/
│       ├── version.rb
│       ├── configuration.rb
│       ├── client.rb
│       ├── notice.rb
│       ├── notice_builder.rb
│       ├── worker.rb
│       ├── filters/
│       │   ├── sanitize_filter.rb
│       │   └── ignore_filter.rb
│       ├── integrations/
│       │   ├── rack.rb
│       │   ├── rails.rb
│       │   ├── sidekiq.rb
│       │   └── active_job.rb
│       └── testing.rb
├── test/
│   ├── test_helper.rb
│   └── checkend/
│       ├── configuration_test.rb
│       ├── client_test.rb
│       ├── notice_test.rb
│       ├── notice_builder_test.rb
│       ├── worker_test.rb
│       ├── filters/
│       │   ├── sanitize_filter_test.rb
│       │   └── ignore_filter_test.rb
│       └── integrations/
│           ├── rack_test.rb
│           ├── rails_test.rb
│           ├── sidekiq_test.rb
│           └── active_job_test.rb
├── checkend-ruby.gemspec
├── Gemfile
├── Rakefile
├── README.md
├── CLAUDE.md
├── ROADMAP.md
├── CHANGELOG.md
├── LICENSE
├── .rubocop.yml
└── .github/
    └── workflows/
        └── ci.yml
```

---

## Future Versions

### Version 1.1 - Enhancements
- [ ] Retry with exponential backoff
- [ ] Offline queueing (persist to disk)
- [ ] Source map support for JavaScript errors
- [ ] Custom transport adapters (Faraday, HTTParty)

### Version 1.2 - Performance
- [ ] Batch sending (multiple notices per request)
- [ ] Sampling configuration
- [ ] Rate limiting on client side

---

## Reference: Checkend Server API

**Endpoint:** `POST /ingest/v1/errors`
**Auth Header:** `Checkend-Ingestion-Key: <ingestion_key>`

**Request Payload:**
```json
{
  "error": {
    "class": "NoMethodError",
    "message": "undefined method 'foo' for nil:NilClass",
    "backtrace": ["app/models/user.rb:42:in `save'", "..."],
    "fingerprint": "custom-grouping-key",
    "tags": ["checkout", "payment"]
  },
  "context": {
    "environment": "production",
    "custom_key": "custom_value"
  },
  "request": {
    "url": "https://example.com/users",
    "method": "POST",
    "params": {},
    "headers": {}
  },
  "user": {
    "id": "123",
    "email": "user@example.com"
  },
  "notifier": {
    "name": "checkend-ruby",
    "version": "1.0.0",
    "language": "ruby",
    "language_version": "3.2.0"
  }
}
```

**Response (201 Created):**
```json
{
  "id": 123,
  "problem_id": 456
}
```

**Error Responses:**
- 401 Unauthorized - Invalid or missing ingestion key
- 422 Unprocessable Entity - Missing error.class
