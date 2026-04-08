require 'functionable'
require 'json'
require 'time'

module Parser
  extend Functionable

  LogEntry = Data.define(:priority, :timestamp, :hostname, :app_name, :proc_id, :msg_id, :message,
                         :parsed)

  JID = 'jid'.freeze
  MIN_SYSLOG_FIELDS = 5
  JSON_PREFIX = ': '.freeze
  MS_PER_SECOND = 1000.0

  def parse_logplex_body(body)
    entries = []
    bytes = body.b
    pos = 0

    while pos < bytes.length
      pos = skip_whitespace(bytes, pos)
      break if pos >= bytes.length

      count, pos = read_octet_count(bytes, pos)
      break unless count

      msg, pos = read_message(bytes, pos, count)
      entry = parse_syslog_message(msg)
      entries << entry if entry
    end

    entries
  end

  #
  # private below here
  #

  def parse_syslog_message(msg)
    return nil if msg.empty? || msg[0] != '<'

    priority, rest = extract_priority(msg)
    return nil unless priority

    fields = rest.split(' ', 6)
    return nil if fields.length < MIN_SYSLOG_FIELDS

    build_entry(priority, fields)
  end

  def skip_whitespace(bytes, pos)
    pos += 1 while pos < bytes.length && " \n\r".include?(bytes[pos])
    pos
  end

  def read_octet_count(bytes, pos)
    count_start = pos
    pos += 1 while pos < bytes.length && bytes[pos].match?(/\d/)
    return nil unless valid_octet_prefix?(bytes, pos, count_start)

    count = bytes[count_start...pos].to_i
    return nil if count <= 0

    [count, pos + 1] # +1 to skip space after count
  end

  def valid_octet_prefix?(bytes, pos, count_start)
    pos < bytes.length && bytes[pos] == ' ' && pos != count_start
  end

  def read_message(bytes, pos, count)
    count = bytes.length - pos if pos + count > bytes.length
    msg = bytes[pos, count].force_encoding('UTF-8')
    [msg, pos + count]
  end

  def extract_priority(msg)
    close_angle = msg.index('>')
    return nil unless close_angle

    priority = msg[1...close_angle].to_i
    rest = msg[(close_angle + 1)..]
    space_idx = rest.index(' ')
    return nil unless space_idx

    [priority, rest[(space_idx + 1)..]]
  end

  def build_entry(priority, fields)
    timestamp = Time.parse(fields[0]).utc
    raw_message = fields[MIN_SYSLOG_FIELDS] ? fields[MIN_SYSLOG_FIELDS].sub(/\A- ?/, '').chomp : ''
    parsed, message = parse_structured_message(raw_message, timestamp)
    message = "#{message} request_id=#{parsed['request_id']}" if parsed&.key?('request_id')
    LogEntry.new(priority:, timestamp:, hostname: fields[1], app_name: fields[2],
                 proc_id: fields[3], msg_id: fields[4], message:, parsed:)
  rescue ArgumentError
    nil
  end

  def parse_structured_message(message, timestamp)
    parsed, message = parse_json_message(message)
    parsed.nil? ? Parser::Router.parse(message, timestamp) : [parsed, message]
  end

  def parse_json_message(message)
    json_start = message.index('{')
    return [nil, message] unless json_start && valid_json_position?(message, json_start)

    parsed = JSON.parse(message[json_start..])
    inner_message = parsed.delete('message') || message
    if parsed.key?('duration') && !parsed.key?(JID)
      parsed['duration'] = parsed['duration'] / MS_PER_SECOND
    end
    [parsed, inner_message]
  rescue JSON::ParserError
    [nil, message]
  end

  def valid_json_position?(message, pos)
    pos.zero? || message[(pos - JSON_PREFIX.length), JSON_PREFIX.length] == JSON_PREFIX
  end

  conceal :parse_syslog_message, :skip_whitespace, :read_octet_count,
          :valid_octet_prefix?, :read_message, :extract_priority,
          :build_entry, :parse_structured_message, :parse_json_message,
          :valid_json_position?
end
