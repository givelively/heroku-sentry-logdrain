require 'functionable'

module Parser
  module Attributes
    extend Functionable

    HTTP_ATTRIBUTE_KEYS = %w[
      method path format controller action status
      view db allocations request_id
    ].freeze

    SIDEKIQ_ATTRIBUTE_KEYS = %w[class queue jid job_status].freeze

    def attributes_for(entry, drain_token)
      attrs = base_attributes(entry, drain_token)
      attrs.merge!(json_attributes(entry.parsed)) if entry.parsed
      attrs
    end

    #
    # private below here
    #

    def base_attributes(entry, drain_token)
      attrs = {
        'heroku.source' => entry.app_name,
        'heroku.dyno' => entry.proc_id
      }
      attrs['heroku.drain_id'] = drain_token if drain_token && !drain_token.empty?
      attrs
    end

    def json_attributes(parsed)
      prefix, keys = if parsed[Parser::JID]
                       ['sidekiq', SIDEKIQ_ATTRIBUTE_KEYS]
                     else
                       ['http', HTTP_ATTRIBUTE_KEYS]
                     end
      attrs = format_attributes(parsed, prefix, keys)
      attrs['duration'] = parsed['duration'].to_s if parsed.key?('duration')
      attrs
    end

    def format_attributes(parsed, prefix, keys)
      keys.each_with_object({}) do |key, hash|
        hash["#{prefix}.#{key}"] = parsed[key].to_s if parsed.key?(key)
      end
    end

    conceal :base_attributes, :json_attributes, :format_attributes
  end
end
