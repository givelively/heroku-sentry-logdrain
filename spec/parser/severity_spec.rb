require 'spec_helper'

RSpec.describe Parser::Severity do
  let(:make_entry) do
    lambda { |parsed|
      Parser::LogEntry.new(priority: 134, timestamp: Time.utc(2026, 1, 1),
                           hostname: 'h', app_name: 'a', proc_id: 'w.1',
                           msg_id: '-', message: 'msg', parsed:)
    }
  end

  describe '.resolve_severity' do
    it 'uses syslog priority for plain entries' do
      expect(described_class.resolve_severity(make_entry.call(nil))).to eq([9, 'INFO'])
    end

    it 'uses HTTP status for parsed entries' do
      entry = make_entry.call('status' => 500)
      expect(described_class.resolve_severity(entry)).to eq([17, 'ERROR'])
    end

    it 'uses severity string for Sidekiq entries' do
      entry = make_entry.call('jid' => 'abc', 'severity' => 'WARN')
      expect(described_class.resolve_severity(entry)).to eq([13, 'WARN'])
    end
  end

  describe '.severity_from_priority' do
    it 'maps emergency to FATAL' do
      expect(described_class.severity_from_priority(40)).to eq([21, 'FATAL'])
    end

    it 'maps informational to INFO' do
      expect(described_class.severity_from_priority(134)).to eq([9, 'INFO'])
    end

    it 'maps error to ERROR' do
      expect(described_class.severity_from_priority(131)).to eq([17, 'ERROR'])
    end
  end
end
