require 'functionable'

module DrainMap
  extend Functionable

  Entry = Data.define(:name, :environment)

  # Parses DRAIN_MAP env var format:
  #   "d.token1=app-name-1:production,d.token2=app-name-2:staging"
  def parse(raw)
    return {} if raw.nil? || raw.empty?

    raw.split(',').each_with_object({}) do |pair, map|
      token, value = pair.split('=', 2)
      next unless token && value

      name, environment = value.strip.split(':', 2)
      unless environment
        raise ArgumentError,
              "DRAIN_MAP entry '#{value.strip}' is missing a :environment suffix"
      end

      map[token.strip] = Entry.new(name:, environment:)
    end
  end

  def app_name_for(drain_token, drain_map)
    drain_map[drain_token]&.name
  end

  def environment_for(drain_token, drain_map)
    drain_map[drain_token]&.environment
  end
end
