require 'functionable'

module Parser
  module Severity
    extend Functionable

    SEVERITY_MASK = 0x07

    # syslog severity → [OTLP severity_number, severity_text]
    SYSLOG_SEVERITY_MAP = {
      0 => [21, 'FATAL'], 1 => [21, 'FATAL'], # emergency, alert
      2 => [17, 'ERROR'], 3 => [17, 'ERROR'], # critical, error
      4 => [13, 'WARN'],  5 => [9, 'INFO'],   # warning, notice
      6 => [9, 'INFO'],   7 => [5, 'DEBUG']   # informational, debug
    }.freeze

    SEVERITY_STRING_MAP = {
      'DEBUG' => [5, 'DEBUG'],
      'INFO' => [9, 'INFO'],
      'WARN' => [13, 'WARN'],
      'ERROR' => [17, 'ERROR'],
      'FATAL' => [21, 'FATAL']
    }.freeze

    HTTP_ERROR_THRESHOLD = 500

    def resolve_severity(entry)
      if entry.parsed && entry.parsed[Parser::JID]
        severity_from_string(entry.parsed['severity'])
      elsif entry.parsed && entry.parsed['status']
        severity_from_http_status(entry.parsed['status'])
      else
        severity_from_priority(entry.priority)
      end
    end

    def severity_from_priority(priority)
      syslog_severity = priority & SEVERITY_MASK
      SYSLOG_SEVERITY_MAP.fetch(syslog_severity, [9, 'INFO'])
    end

    #
    # private below here
    #

    def severity_from_http_status(status)
      status >= HTTP_ERROR_THRESHOLD ? [17, 'ERROR'] : [9, 'INFO']
    end

    def severity_from_string(severity_str)
      SEVERITY_STRING_MAP.fetch(severity_str&.upcase, [9, 'INFO'])
    end

    conceal :severity_from_http_status, :severity_from_string
  end
end
