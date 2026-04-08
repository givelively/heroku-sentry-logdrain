require 'spec_helper'

RSpec.describe OTLP do
  let(:exporter) { OpenTelemetry::SDK::Logs::Export::InMemoryLogRecordExporter.new }

  let(:drain_entries) do
    names = %w[my-app app-a app-b test-app]
    entries = names.map { |n| DrainMap::Entry.new(name: n, environment: nil) }
    entries << DrainMap::Entry.new(name: 'my-app', environment: 'production')
    entries
  end

  before { described_class.setup(exporter:, drain_entries:) }

  define_method(:records) do
    described_class.flush
    exporter.emitted_log_records
  end

  define_method(:parse_syslog) do |syslog_msg|
    body = "#{syslog_msg.bytesize} #{syslog_msg}"
    Parser.parse_logplex_body(body)
  end

  describe '.emit_logs' do
    context 'with a plain text log entry' do
      let(:syslog_msg) do
        '<134>1 2012-11-30T06:45:29+00:00 host app web.3 - State changed from starting to up'
      end
      let(:entries) { parse_syslog(syslog_msg) }

      it 'emits a log record with the correct body' do
        described_class.emit_logs(entries, 'my-app', 'd.abc123')

        expect(records.length).to eq(1)
        expect(records.first.body).to eq('State changed from starting to up')
      end

      it 'sets heroku attributes' do
        described_class.emit_logs(entries, 'my-app', 'd.abc123')

        attrs = records.first.attributes
        expect(attrs['heroku.source']).to eq('app')
        expect(attrs['heroku.dyno']).to eq('web.3')
        expect(attrs['heroku.drain_id']).to eq('d.abc123')
      end

      it 'uses syslog priority for severity' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.severity_number).to eq(9)
        expect(records.first.severity_text).to eq('INFO')
      end

      it 'omits drain_id when not present' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.attributes.keys).not_to include('heroku.drain_id')
      end

      it 'sets service.name from app_name on the resource' do
        described_class.emit_logs(entries, 'my-app')

        service_name = records.first.resource.attribute_enumerator.to_h['service.name']
        expect(service_name).to eq('my-app')
      end

      it 'sets deployment.environment on the resource' do
        described_class.emit_logs(entries, 'my-app', 'd.abc123', environment: 'production')

        env = records.first.resource.attribute_enumerator.to_h['deployment.environment']
        expect(env).to eq('production')
      end
    end

    context 'with a parsed JSON log entry' do
      let(:json_body) do
        '{"method":"POST","path":"/carts","format":"json",' \
          '"controller":"CartsController","action":"create",' \
          '"status":201,"duration":40.64,"view":0.4,"db":19.55,' \
          '"request_id":"abc-123","@timestamp":"2026-04-03T19:57:09.993Z",' \
          '"@version":"1","message":"[201] POST /carts (CartsController#create)"}'
      end
      let(:syslog_msg) { "<134>1 2026-04-03T19:57:09+00:00 host app web.1 - #{json_body}" }
      let(:entries) { parse_syslog(syslog_msg) }

      it 'uses the extracted message as body' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.body).to eq(
          '[201] POST /carts (CartsController#create) request_id=abc-123'
        )
      end

      it 'includes parsed fields as http.* attributes' do
        described_class.emit_logs(entries, 'my-app')

        attrs = records.first.attributes
        expect(attrs['http.method']).to eq('POST')
        expect(attrs['http.path']).to eq('/carts')
        expect(attrs['http.controller']).to eq('CartsController')
        expect(attrs['http.action']).to eq('create')
        expect(attrs['http.status']).to eq('201')
        expect(attrs['duration']).to eq('0.04064')
        expect(attrs['http.request_id']).to eq('abc-123')
      end

      it 'derives severity from HTTP status' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.severity_number).to eq(9)
        expect(records.first.severity_text).to eq('INFO')
      end

      context 'when HTTP status is 500+' do
        let(:json_body) do
          '{"status":500,"message":"Internal Server Error"}'
        end

        it 'sets severity to ERROR' do
          described_class.emit_logs(entries, 'my-app')

          expect(records.first.severity_number).to eq(17)
          expect(records.first.severity_text).to eq('ERROR')
        end
      end
    end

    context 'with a Sidekiq job log entry' do
      let(:json_body) do
        '{"severity":"INFO","class":"Metrics::SendMetricWorker",' \
          '"queue":"in_minutes","jid":"b898f36d13f7a6f0e60ffab7",' \
          '"job_status":"done","duration":0.018,' \
          '"message":"Metrics::SendMetricWorker JID-b898f36d13f7a6f0e60ffab7: done: 0.018 sec",' \
          '"@timestamp":"2026-04-07T22:59:17.000Z","@version":"1"}'
      end
      let(:syslog_msg) { "<134>1 2026-04-07T22:59:17+00:00 host app worker.1 - #{json_body}" }
      let(:entries) { parse_syslog(syslog_msg) }

      it 'includes Sidekiq fields as sidekiq.* attributes' do
        described_class.emit_logs(entries, 'my-app')

        attrs = records.first.attributes
        expect(attrs['sidekiq.class']).to eq('Metrics::SendMetricWorker')
        expect(attrs['sidekiq.queue']).to eq('in_minutes')
        expect(attrs['sidekiq.jid']).to eq('b898f36d13f7a6f0e60ffab7')
        expect(attrs['sidekiq.job_status']).to eq('done')
        expect(attrs['duration']).to eq('0.018')
      end

      it 'does not include http.* attributes' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.attributes.keys.none? { |k| k.start_with?('http.') }).to be(true)
      end

      it 'derives severity from the severity string field' do
        described_class.emit_logs(entries, 'my-app')

        expect(records.first.severity_number).to eq(9)
        expect(records.first.severity_text).to eq('INFO')
      end

      context 'when severity is ERROR' do
        let(:json_body) do
          '{"severity":"ERROR","class":"Metrics::SendMetricWorker",' \
            '"queue":"in_minutes","jid":"b898f36d13f7a6f0e60ffab7",' \
            '"job_status":"error","duration":0.018,' \
            '"message":"Metrics::SendMetricWorker JID-b898f36d13f7a6f0e60ffab7: error",' \
            '"@timestamp":"2026-04-07T22:59:17.000Z","@version":"1"}'
        end

        it 'sets severity to ERROR' do
          described_class.emit_logs(entries, 'my-app')

          expect(records.first.severity_number).to eq(17)
          expect(records.first.severity_text).to eq('ERROR')
        end
      end
    end

    context 'with multiple entries for different app names' do
      let(:make_entry) do
        lambda do |msg|
          syslog_msg = "<134>1 2026-04-03T19:57:09+00:00 host app web.1 - #{msg}"
          parse_syslog(syslog_msg).first
        end
      end

      it 'emits one record per entry' do
        described_class.emit_logs([make_entry.call('first'), make_entry.call('second')], 'my-app')

        expect(records.length).to eq(2)
        expect(records.map(&:body)).to eq(%w[first second])
      end

      it 'uses separate service.name resources for different app names' do
        described_class.emit_logs([make_entry.call('from-app-a')], 'app-a')
        described_class.emit_logs([make_entry.call('from-app-b')], 'app-b')

        names = records.map { |r| r.resource.attribute_enumerator.to_h['service.name'] }
        expect(names).to eq(%w[app-a app-b])
      end
    end

    context 'when the logger cache is unavailable' do
      it 'returns an error message instead of raising' do
        described_class.instance_variable_set(:@loggers, nil)

        entry = parse_syslog('<134>1 2026-04-03T19:57:09+00:00 host app web.1 - hi').first

        result = described_class.emit_logs([entry], 'my-app')
        expect(result).to be_a(String)
      ensure
        described_class.setup(exporter:, drain_entries:)
      end
    end
  end
end
