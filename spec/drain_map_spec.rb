require 'spec_helper'

RSpec.describe DrainMap do
  describe '.parse' do
    it 'parses comma-separated token=app:environment pairs' do
      result = described_class.parse('d.abc=my-app:production,d.def=other-app:staging')

      expect(result).to eq(
        'd.abc' => DrainMap::Entry.new(name: 'my-app', environment: 'production'),
        'd.def' => DrainMap::Entry.new(name: 'other-app', environment: 'staging')
      )
    end

    context 'without environment suffix' do
      it 'raises an ArgumentError' do
        expect { described_class.parse('d.abc=my-app') }
          .to raise_error(ArgumentError, /missing a :environment suffix/)
      end
    end

    context 'with nil' do
      it 'returns empty hash' do
        expect(described_class.parse(nil)).to eq({})
      end
    end

    context 'with empty string' do
      it 'returns empty hash' do
        expect(described_class.parse('')).to eq({})
      end
    end

    context 'with whitespace around entries' do
      it 'strips whitespace' do
        result = described_class.parse(' d.abc = my-app:production , d.def = other-app:staging ')

        expect(result).to eq(
          'd.abc' => DrainMap::Entry.new(name: 'my-app', environment: 'production'),
          'd.def' => DrainMap::Entry.new(name: 'other-app', environment: 'staging')
        )
      end
    end
  end

  describe '.app_name_for' do
    let(:drain_map) { described_class.parse('d.abc=my-app:production,d.def=other-app:staging') }

    context 'with a known drain token' do
      it 'returns the mapped app name' do
        expect(described_class.app_name_for('d.abc', drain_map)).to eq('my-app')
      end
    end

    context 'with an unknown drain token' do
      it 'returns nil' do
        expect(described_class.app_name_for('d.unknown', drain_map)).to be_nil
      end
    end

    context 'with nil drain token' do
      it 'returns nil' do
        expect(described_class.app_name_for(nil, drain_map)).to be_nil
      end
    end
  end

  describe '.environment_for' do
    let(:drain_map) { described_class.parse('d.abc=my-app:production,d.def=other-app:staging') }

    it 'returns the environment for a known token' do
      expect(described_class.environment_for('d.abc', drain_map)).to eq('production')
    end

    it 'returns nil for an unknown token' do
      expect(described_class.environment_for('d.unknown', drain_map)).to be_nil
    end
  end
end
