# Heroku Log Drain → Sentry OTLP Proxy

A small Ruby HTTP server that receives Heroku HTTPS log drain POSTs, parses the syslog-formatted log lines, converts them to OpenTelemetry OTLP log format, and forwards them to Sentry's OTLP logs endpoint.

```
Heroku Logplex → HTTPS POST (syslog batches) → This app → OTLP HTTP POST → Sentry
```

## Environment Variables

| Var | Description |
|-----|-------------|
| `SENTRY_DSN` | Sentry DSN for error tracking of this proxy itself (required) |
| `SENTRY_OTLP_LOGS_URL` | Sentry's OTLP logs endpoint (required) |
| `OTLP_HEADERS` | OTLP auth headers from Sentry, required (e.g. `x-sentry-auth=sentry sentry_key=abc`) |
| `DRAIN_MAP` | Drain token to app name mapping (e.g. `d.abc=my-app,d.def=other-app`) |
| `PORT` | Listen port (default: `5000`, set automatically by Heroku) |

Find `SENTRY_OTLP_LOGS_URL` and `OTLP_HEADERS` in Sentry under **Project Settings → Client Keys (DSN) → OpenTelemetry (OTLP)**.

## Deploy to Heroku

```bash
heroku create my-log-drain-proxy

heroku config:set \
  SENTRY_DSN="https://your-key@o123.ingest.us.sentry.io/456" \
  SENTRY_OTLP_LOGS_URL="https://o{ORG_ID}.ingest.us.sentry.io/api/{PROJECT_ID}/integration/otlp/v1/logs" \
  OTLP_HEADERS="x-sentry-auth=sentry sentry_key=your-public-key"

git push heroku main
heroku labs:enable runtime-dyno-metadata # Enable Sentry tracking of releases
```

## Adding a log drain

Use `bin/add_drain` to add a source app and automatically configure the drain mapping:

```bash
bin/add_drain my-source-app my-log-drain-proxy
```

This will print out the steps to add a log drain. Follow the steps


## Source App Setup

This proxy works with any Heroku app since Heroku Logplex delivers all logs in syslog format. Platform logs (router, dyno, system) work out of the box with no app changes.

For **application logs**, structured JSON logging via [Logstash](https://github.com/dwbutler/logstash-logger) (or any logger that outputs JSON) unlocks richer attributes in Sentry. When the log message body is JSON, the proxy extracts these fields as OTLP attributes:

| Field | Example | Notes |
|-------|---------|-------|
| `method` | `GET` | HTTP method |
| `path` | `/carts` | Request path |
| `format` | `json` | Response format |
| `controller` | `CartsController` | Rails controller |
| `action` | `create` | Rails action |
| `status` | `201` | HTTP status code |
| `view` | `0.4` | View rendering time (ms) |
| `db` | `19.55` | Database time (ms) |
| `allocations` | `9631` | Memory allocations |
| `request_id` | `abc-123` | Request identifier |
| `message` | `[201] POST /carts` | Used as the log body |

These fields match the default output of [logstash-logger](https://github.com/dwbutler/logstash-logger) with [lograge](https://github.com/roidrage/lograge) in a Rails app — but any app that logs JSON with these keys will work. Non-JSON log lines are forwarded as plain text.

## Sidekiq

Sidekiq job logs are detected by the presence of a `jid` field and get `sidekiq.*` attributes instead:

| Field | Example | Notes |
|-------|---------|-------|
| `class` | `Webhooks::Stripe::ChargeSucceededWorker` | Worker class name |
| `queue` | `in_seconds` | Queue the job ran on |
| `jid` | `88a9623849cc7a1c5efe6fd5` | Job ID |
| `job_status` | `done` | Completion status (`done`, `error`, `retry`) |
| `message` | `ChargeSucceededWorker JID-...: done: 0.467 sec` | Used as the log body |

All log types with timing data get a `duration` OTLP attribute in seconds (per [OTel convention](https://opentelemetry.io/docs/specs/semconv/general/metrics/)). Router duration is computed from `connect` + `service`, Rails duration is converted from milliseconds, and Sidekiq duration is passed through as-is.

Severity is derived from Sidekiq's `severity` field (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`) rather than the syslog priority.

## Endpoints

- `POST /` — Receives Heroku log drain payloads
- `GET /health` — Returns 200


## Local Development

Requires Ruby. See [Gemfile](Gemfile)

```bash
bundle install
bundle exec rspec
bin/lint
```

## Why tho?

Heroku Cedar doesn't support telemetry drains (only Fir does) and Sentry doesn't accept raw syslog. This proxy bridges the gap so Heroku platform logs (router, dyno, system) appear in Sentry alongside application errors. This will be unnecessary if Sentry adds native Heroku log drain support ([getsentry/sentry#91727](https://github.com/getsentry/sentry/issues/91727)).
