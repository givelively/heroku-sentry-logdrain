require 'spec_helper'

# SENTRY_DSN intentionally unset in test to disable Sentry
ENV['SENTRY_OTLP_LOGS_URL'] ||= 'https://sentry.example.com/api/123/otlp/v1/logs'
ENV['OTLP_HEADERS'] ||= 'x-sentry-auth=test-key'

require_relative '../app'

RSpec.describe App do
  include Rack::Test::Methods

  let(:app) { described_class }
  let(:exporter) { OpenTelemetry::SDK::Logs::Export::InMemoryLogRecordExporter.new }
  let(:default_token) { 'd.test-token' }

  before do
    app.drain_map.clear
    app.drain_map[default_token] = DrainMap::Entry.new(name: 'test-app', environment: 'test')
    OTLP.setup(exporter:, drain_entries: app.drain_map.values)
  end

  define_method(:records) do
    OTLP.flush
    exporter.emitted_log_records
  end

  describe 'GET /health' do
    it 'returns 200' do
      get '/health'

      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /logs' do
    let(:logplex_body) do
      '82 <40>1 2012-11-30T06:45:29+00:00 host app web.3 - State changed from starting to up'
    end

    context 'with valid log data' do
      it 'emits to OTLP and returns 200' do
        post '/', logplex_body,
             'CONTENT_TYPE' => 'application/logplex-1',
             'HTTP_LOGPLEX_DRAIN_TOKEN' => default_token

        expect(last_response.status).to eq(200)
        expect(records).not_to be_empty
      end
    end

    context 'with empty body' do
      it 'returns 200 without emitting any records' do
        post '/', '',
             'CONTENT_TYPE' => 'application/logplex-1',
             'HTTP_LOGPLEX_DRAIN_TOKEN' => default_token

        expect(last_response.status).to eq(200)
        expect(records).to be_empty
      end
    end

    context 'when drain map is empty' do
      before do
        app.drain_map.clear
      end

      it 'accepts requests and emits using the fallback service.name' do
        post '/', logplex_body,
             'CONTENT_TYPE' => 'application/logplex-1',
             'HTTP_LOGPLEX_DRAIN_TOKEN' => 'd.some-token'

        expect(last_response.status).to eq(200)
        resource = records.first.resource.attribute_enumerator.to_h
        expect(resource['service.name']).to eq('unknown')
      end

      it 'falls back to unknown when no drain token is present' do
        post '/', logplex_body, 'CONTENT_TYPE' => 'application/logplex-1'

        expect(last_response.status).to eq(200)
        resource = records.first.resource.attribute_enumerator.to_h
        expect(resource['service.name']).to eq('unknown')
      end
    end

    context 'when drain map is configured' do
      before do
        app.drain_map.clear
        app.drain_map['d.mapped-token'] =
          DrainMap::Entry.new(name: 'mapped-app', environment: 'production')
        OTLP.setup(exporter:, drain_entries: app.drain_map.values)
      end

      context 'with a mapped drain token' do
        it 'returns 200 and uses the mapped app name as service.name' do
          post '/', logplex_body,
               'CONTENT_TYPE' => 'application/logplex-1',
               'HTTP_LOGPLEX_DRAIN_TOKEN' => 'd.mapped-token'

          expect(last_response.status).to eq(200)
          resource = records.first.resource.attribute_enumerator.to_h
          service_name = resource['service.name']
          expect(service_name).to eq('mapped-app')
        end
      end

      context 'with an unmapped drain token' do
        it 'returns 401 without emitting any records' do
          post '/', logplex_body,
               'CONTENT_TYPE' => 'application/logplex-1',
               'HTTP_LOGPLEX_DRAIN_TOKEN' => 'd.unknown-token'

          expect(last_response.status).to eq(401)
          expect(records).to be_empty
        end
      end

      context 'with no drain token' do
        it 'returns 401' do
          post '/', logplex_body, 'CONTENT_TYPE' => 'application/logplex-1'

          expect(last_response.status).to eq(401)
        end
      end
    end

    context 'with parsed JSON log body' do
      let(:json_msg) do
        '{"method":"POST","path":"/carts","controller":"CartsController",' \
          '"action":"create","status":201,"duration":40.64,' \
          '"message":"[201] POST /carts (CartsController#create)"}'
      end

      let(:syslog_msg) { "<134>1 2026-04-03T19:57:09+00:00 host app web.1 - #{json_msg}" }
      let(:logplex_body) { "#{syslog_msg.bytesize} #{syslog_msg}" }

      it 'emits the extracted message and parsed attributes' do
        post '/', logplex_body,
             'CONTENT_TYPE' => 'application/logplex-1',
             'HTTP_LOGPLEX_DRAIN_TOKEN' => default_token

        expect(last_response.status).to eq(200)

        record = records.first
        attrs = record.attributes
        expect(record.body).to eq('[201] POST /carts (CartsController#create)')
        expect(attrs['http.controller']).to eq('CartsController')
        expect(attrs['http.method']).to eq('POST')
      end
    end

    context 'when the logger cache is unavailable' do
      before { OTLP.instance_variable_set(:@loggers, nil) }
      after { OTLP.setup(exporter:, drain_entries: app.drain_map.values) }

      it 'still returns 200 to avoid blocking the drain' do
        post '/', logplex_body,
             'CONTENT_TYPE' => 'application/logplex-1',
             'HTTP_LOGPLEX_DRAIN_TOKEN' => default_token

        expect(last_response.status).to eq(200)
      end
    end
  end
end
