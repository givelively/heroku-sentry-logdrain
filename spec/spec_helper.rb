ENV['RACK_ENV'] = 'test'

require 'rack/test'
require 'webmock/rspec'

require_relative '../lib/drain_map'
require_relative '../lib/parser'
require_relative '../lib/parser/severity'
require_relative '../lib/parser/attributes'
require_relative '../lib/parser/router'
require_relative '../lib/otlp'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
end
