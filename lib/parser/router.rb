require 'functionable'

module Parser
  module Router
    extend Functionable

    PAIR_PATTERN = /(\w+)=("(?:[^"]*)"|\S+)/
    ATTRIBUTE_KEYS = %w[method path status service connect request_id].freeze
    MS_PER_SECOND = 1000.0
    TIMESTAMP_PRECISION = 3

    def parse(message, timestamp)
      return [nil, message] unless message.include?('method=') && message.include?('path=')

      pairs = message.scan(PAIR_PATTERN)
      return [nil, message] if pairs.empty?

      attrs, extras = pairs.partition { |key, _| ATTRIBUTE_KEYS.include?(key) }
      parsed = build_parsed(attrs, timestamp)
      [parsed, build_body(parsed, extras)]
    end

    #
    # private below here
    #

    def build_parsed(pairs, timestamp)
      hash = pairs.each_with_object({}) do |(key, raw_value), h|
        value = raw_value.start_with?('"') ? raw_value[1..-2] : raw_value
        h[key] = coerce_value(value)
      end
      hash['duration'] = ((hash['service'] || 0) + (hash['connect'] || 0)) / MS_PER_SECOND
      hash['@timestamp'] = timestamp.iso8601(TIMESTAMP_PRECISION)
      hash
    end

    def build_body(parsed, extras)
      body = "[#{parsed['status']}] #{parsed['method']} #{parsed['path']}"
      extras.each { |key, value| body += " #{key}=#{value}" }
      return body unless parsed['connect'] || parsed['service']

      body + " (connect=#{parsed['connect']}ms service=#{parsed['service']}ms)"
    end

    def coerce_value(value)
      if value.end_with?('ms')
        value.chomp('ms').to_f
      elsif value.match?(/\A\d+\z/)
        value.to_i
      else
        value
      end
    end

    conceal :build_parsed, :build_body, :coerce_value
  end
end
