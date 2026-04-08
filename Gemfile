source 'https://rubygems.org'

ruby '4.0.2'

gem 'functionable'
gem 'opentelemetry-exporter-otlp-logs'
gem 'opentelemetry-logs-sdk'
gem 'puma'
gem 'sentry-ruby'
gem 'sinatra'

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'webmock'
end

group :development, :test do
  gem 'benchmark'
  gem 'bundler-audit', require: false
  gem 'gl_lint', require: false
  gem 'gl_rubocop', require: false
  gem 'tsort'
end
