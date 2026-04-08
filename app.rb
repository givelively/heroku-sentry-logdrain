require 'sentry-ruby'
require 'sinatra/base'
require_relative 'lib/drain_map'
require_relative 'lib/parser'
require_relative 'lib/parser/severity'
require_relative 'lib/parser/attributes'
require_relative 'lib/parser/router'
require_relative 'lib/otlp'

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN', nil)
end

class App < Sinatra::Base
  HTTP_OK = 200
  HTTP_UNAUTHORIZED = 401

  use Sentry::Rack::CaptureExceptions

  configure do
    set :drain_map, DrainMap.parse(ENV.fetch('DRAIN_MAP', nil))

    OTLP.setup(
      sentry_url: ENV.fetch('SENTRY_OTLP_LOGS_URL'),
      headers: ENV.fetch('OTLP_HEADERS'),
      drain_entries: settings.drain_map.values
    )

    at_exit { OTLP.shutdown }
  end

  get '/health' do
    status HTTP_OK
    body ''
  end

  post '/' do
    drain_token = request.env['HTTP_LOGPLEX_DRAIN_TOKEN']

    if !settings.drain_map.empty? && !settings.drain_map.key?(drain_token)
      halt HTTP_UNAUTHORIZED, 'unauthorized'
    end

    raw_body = request.body.read
    entries = Parser.parse_logplex_body(raw_body)

    if entries.any?
      app_name = DrainMap.app_name_for(drain_token,
                                       settings.drain_map) || drain_token || 'unknown'
      environment = DrainMap.environment_for(drain_token, settings.drain_map)
      err = OTLP.emit_logs(entries, app_name, drain_token, environment:)
      logger.error("Error sending to Sentry: #{err}") if err
    end

    content_type 'text/plain'
    headers 'Content-Length' => '0'
    status HTTP_OK
    body ''
  end
end
