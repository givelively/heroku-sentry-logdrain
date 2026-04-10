require 'opentelemetry-logs-sdk'
require 'opentelemetry-exporter-otlp-logs'

module OTLP
  FALLBACK_KEY = ['unknown', nil].freeze

  class << self
    def setup(sentry_url: nil, headers: nil, exporter: nil, drain_entries: [])
      @exporter = exporter || OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
        endpoint: sentry_url,
        headers: parse_headers(headers)
      )
      @providers = {}
      @loggers = {}
      drain_entries.each { |entry| build_logger(entry.name, entry.environment) }
      build_logger(*FALLBACK_KEY)
    end

    def flush
      @providers&.each_value(&:force_flush)
    end

    def shutdown
      @providers&.each_value(&:shutdown)
    end

    def emit_logs(entries, app_name, drain_token = nil, environment: nil)
      key = [app_name, environment]
      logger = @loggers[key] || @loggers[FALLBACK_KEY]
      entries.each { |entry| emit_entry(entry, drain_token, logger) }
      nil
    rescue StandardError => e
      e.message
    end

    private

    def parse_headers(raw)
      return {} if raw.nil? || raw.empty?

      raw.split(',').each_with_object({}) do |pair, hash|
        key, value = pair.split('=', 2)
        hash[key.strip] = value.strip if key && value
      end
    end

    def build_logger(app_name, environment)
      key = [app_name, environment]
      processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(@exporter)
      attrs = { 'service.name' => app_name }
      attrs['deployment.environment'] = environment if environment
      resource = OpenTelemetry::SDK::Resources::Resource.create(attrs)
      provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(resource:)
      provider.add_log_record_processor(processor)
      @providers[key] = provider
      @loggers[key] = provider.logger(name: 'heroku-log-drain')
    end

    def emit_entry(entry, drain_token, logger)
      sev_num, sev_text = Parser::Severity.resolve_severity(entry)
      trace_id = parse_trace_id(entry.parsed&.dig('trace_id'))
      logger.on_emit(
        timestamp: entry.timestamp,
        severity_number: sev_num,
        severity_text: sev_text,
        body: entry.message,
        attributes: Parser::Attributes.attributes_for(entry, drain_token),
        trace_id:
      )
    end

    # Converts a 32-char hex trace_id to the 16-byte binary format
    # that OpenTelemetry's on_emit expects. Sentry uses this to link
    # logs to traces from the originating application.
    def parse_trace_id(hex)
      return nil unless hex.is_a?(String) && hex.match?(/\A[0-9a-f]{32}\z/)

      [hex].pack('H32')
    end
  end
end
