require 'spec_helper'

RSpec.describe Parser do
  describe '.parse_logplex_body' do
    it 'parses multiple syslog messages' do
      body = <<~LOGPLEX.chomp
        83 <40>1 2012-11-30T06:45:29+00:00 host app web.3 - State changed from starting to up
        119 <40>1 2012-11-30T06:45:26+00:00 host app web.3 - Starting process with command `bundle exec rackup config.ru -p 24405`
      LOGPLEX

      entries = described_class.parse_logplex_body(body)

      expect(entries.length).to eq(2)

      expect(entries[0].priority).to eq(40)
      expect(entries[0].app_name).to eq('app')
      expect(entries[0].proc_id).to eq('web.3')
      expect(entries[0].message).to eq('State changed from starting to up')
      expect(entries[0].parsed).to be_nil
      expect(entries[0].timestamp).to eq(Time.utc(2012, 11, 30, 6, 45, 29))

      expect(entries[1].message).to eq(
        'Starting process with command `bundle exec rackup config.ru -p 24405`'
      )
    end

    context 'with router key=value log messages' do
      let(:syslog_msg) do
        '<158>1 2012-11-30T06:45:29+00:00 host heroku router - ' \
          'at=info method=GET path="/" host=example.com request_id=abc-123 ' \
          'fwd="1.2.3.4" dyno=web.1 connect=1ms service=18ms status=200 bytes=525'
      end
      let(:router_body) { "#{syslog_msg.bytesize} #{syslog_msg}" }
      let(:message_target) do
        '[200] GET / at=info host=example.com fwd="1.2.3.4" dyno=web.1 bytes=525 (connect=1.0ms service=18.0ms) request_id=abc-123'
      end
      let(:parsed_target) do
        {
          'method' => 'GET',
          'path' => '/',
          'status' => 200,
          'service' => 18.0,
          'connect' => 1.0,
          'duration' => 0.019,
          'request_id' => 'abc-123',
          '@timestamp' => '2012-11-30T06:45:29.000Z'
        }
      end

      it 'parses router fields into parsed' do
        entry = described_class.parse_logplex_body(router_body).first

        expect(entry.message).to eq(message_target)
        expect(entry.parsed).to eq(parsed_target)
      end
    end

    context 'with parsed JSON messages' do
      let(:json_body) do
        '{"method":"POST","path":"/carts","format":"json",' \
          '"controller":"CartsController","action":"create",' \
          '"status":201,"duration":40.64,"view":0.4,"db":19.55,' \
          '"request_id":"abc-123","@timestamp":"2026-04-03T19:57:09.993Z",' \
          '"@version":"1","message":"[201] POST /carts (CartsController#create)"}'
      end
      let(:syslog_msg) { "<134>1 2026-04-03T19:57:09+00:00 host app web.1 - #{json_body}" }
      let(:body) { "#{syslog_msg.bytesize} #{syslog_msg}" }
      let(:parsed_target) do
        {
          'method' => 'POST',
          'path' => '/carts',
          'format' => 'json',
          'controller' => 'CartsController',
          'action' => 'create',
          'status' => 201,
          'duration' => 0.04064,
          'view' => 0.4,
          'db' => 19.55,
          'request_id' => 'abc-123',
          '@timestamp' => '2026-04-03T19:57:09.993Z',
          '@version' => '1'
        }
      end

      let(:message_target) { '[201] POST /carts (CartsController#create) request_id=abc-123' }

      it 'parses message and parsed fields' do
        entry = described_class.parse_logplex_body(body).first

        expect(entry.message).to eq(message_target)
        expect(entry.parsed).to eq(parsed_target)
      end
    end

    context 'with sidekiq JSON message' do
      let(:json_body) do
        '2026-04-07T22:59:40.813228+00:00 app[worker_in_seconds_and_minutes.1]: ' \
          '{"severity":"INFO","retry":true,"queue":"in_minutes",' \
          '"args":[{"event_group":"vendor_api_call","vendor":"intercom",' \
          '"message":"Updating intercom contact",' \
          '"user_id":"a44cd094-4613-4696-b3cd-6e75565d7d45",' \
          '"timestamp":"2026-04-07T22:59:40+00:00","environment":"production"}],' \
          '"class":"Metrics::SendMetricWorker","jid":"937042823a66106763bc2fe0",' \
          '"created_at":"2026-04-07T22:59:40.785Z",' \
          '"sentry_user":{"id":null,"username":null,"ip_address":"15.158.54.78"},' \
          '"trace_propagation_headers":{' \
          '"sentry-trace":"7e9ccdad1aa24fab84cced192970dec6-9f26a144f9c24a5e-0",' \
          '"baggage":"sentry-trace_id=7e9ccdad1aa24fab84cced192970dec6,sentry-sample_rate=0.001,' \
          'sentry-sampled=false,sentry-environment=production,' \
          'sentry-release=97716466be65006607bbfaf0a595096fbe9121de,' \
          'sentry-public_key=566034783d2d45de86e5217dc9b8b1e4"},' \
          '"enqueued_at":"2026-04-07T22:59:40.786Z",' \
          '"message":"Metrics::SendMetricWorker JID-937042823a66106763bc2fe0: done: 0.026 sec",' \
          '"pid":2,"duration":0.026,"job_status":"done",' \
          '"completed_at":"2026-04-07T22:59:40.813Z","max_retries":2,' \
          '"@timestamp":"2026-04-07T22:59:40.813Z","@version":"1"}'
      end
      let(:syslog_msg) do
        "<134>1 2026-04-07T22:59:40+00:00 host app worker_in_seconds_and_minutes.1 - #{json_body}"
      end
      let(:body) { "#{syslog_msg.bytesize} #{syslog_msg}" }
      let(:message_target) do
        'Metrics::SendMetricWorker JID-937042823a66106763bc2fe0: done: 0.026 sec'
      end
      let(:parsed_target) do
        {
          'severity' => 'INFO',
          'retry' => true,
          'queue' => 'in_minutes',
          'args' => [{ 'event_group' => 'vendor_api_call', 'vendor' => 'intercom',
                       'message' => 'Updating intercom contact',
                       'user_id' => 'a44cd094-4613-4696-b3cd-6e75565d7d45',
                       'timestamp' => '2026-04-07T22:59:40+00:00',
                       'environment' => 'production' }],
          'class' => 'Metrics::SendMetricWorker',
          'jid' => '937042823a66106763bc2fe0',
          'created_at' => '2026-04-07T22:59:40.785Z',
          'sentry_user' => { 'id' => nil, 'username' => nil, 'ip_address' => '15.158.54.78' },
          'trace_propagation_headers' => {
            'sentry-trace' => '7e9ccdad1aa24fab84cced192970dec6-9f26a144f9c24a5e-0',
            'baggage' => 'sentry-trace_id=7e9ccdad1aa24fab84cced192970dec6,' \
                         'sentry-sample_rate=0.001,sentry-sampled=false,' \
                         'sentry-environment=production,' \
                         'sentry-release=97716466be65006607bbfaf0a595096fbe9121de,' \
                         'sentry-public_key=566034783d2d45de86e5217dc9b8b1e4'
          },
          'enqueued_at' => '2026-04-07T22:59:40.786Z',
          'pid' => 2,
          'duration' => 0.026,
          'job_status' => 'done',
          'completed_at' => '2026-04-07T22:59:40.813Z',
          'max_retries' => 2,
          '@timestamp' => '2026-04-07T22:59:40.813Z',
          '@version' => '1'
        }
      end

      it 'parses message and parsed fields' do
        entry = described_class.parse_logplex_body(body).first

        expect(entry.message).to eq(message_target)
        expect(entry.parsed).to eq(parsed_target)
      end
    end

    it 'returns empty array for empty body' do
      expect(described_class.parse_logplex_body('')).to eq([])
    end

    it 'skips malformed messages' do
      body = "5 junk\n" \
             '83 <40>1 2012-11-30T06:45:29+00:00 host app web.3 - ' \
             'State changed from starting to up'

      entries = described_class.parse_logplex_body(body)

      expect(entries.length).to eq(1)
      expect(entries[0].message).to eq('State changed from starting to up')
    end
  end
end
