require 'time'
require 'rack'

class MoesifHelpers
  def initialize(debug)
    @debug = debug
  end

  def log_debug(message)
    return unless @debug

    puts("#{Time.now} [Moesif Middleware] PID #{Process.pid} TID #{Thread.current.object_id} #{message}")
  end

  def format_replacement_body(replacement_body, original_body)
    # replacement_body is an hash or array json in this case.
    # but original body could be in chunks already. we want to follow suit.
    return original_body if replacement_body.nil?

    if original_body.instance_of?(Hash) || original_body.instance_of?(Array)
      log_debug 'original_body is a hash or array return as is'
      return replacement_body
    end

    if original_body.is_a? String
      log_debug 'original_body is a string, return a string format'
      return replacement_body.to_json.to_s
    end

    if original_body.respond_to?(:each) && original_body.respond_to?(:inject)
      # we know it is an chunks
      log_debug 'original_body respond to iterator, must likely chunks'
      [replacement_body.to_json.to_s]
    end

    [replacement_body.to_json.to_s]
  rescue StandardError => e
    log_debug 'failed to convert replacement body ' + e.to_s
    [replacement_body.to_json.to_s]
  end

  def parse_multipart(multipart_form_data, content_type)
    log_debug("try to parse multiple part #{content_type}")

    sanitized_multipart_form_data = multipart_form_data.gsub(/\r?\n/, "\r\n")

    io = StringIO.new(sanitized_multipart_form_data)
    tempfile = Rack::Multipart::Parser::TEMPFILE_FACTORY
    bufsize = Rack::Multipart::Parser::BUFSIZE
    query_parser = Rack::Utils.default_query_parser
    result = Rack::Multipart::Parser.parse(io, sanitized_multipart_form_data.length, content_type, tempfile, bufsize,
                                           query_parser)

    log_debug('multipart parse result')
    log_debug(result.inspect)

    # this is a hash should be treated as JSON down the road.
    result.params
  end
end
