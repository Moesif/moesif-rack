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

  def decompress_gzip_body(moesif_api_response)
    # Decompress gzip response body

    # Check if the content-encoding header exist and is of type zip
    if moesif_api_response.headers.key?(:content_encoding) && moesif_api_response.headers[:content_encoding].eql?('gzip')

      # Create a GZipReader object to read data
      gzip_reader = Zlib::GzipReader.new(StringIO.new(moesif_api_response.raw_body.to_s))

      # Read the body
      uncompressed_string = gzip_reader.read

      # Return the parsed body
      JSON.parse(uncompressed_string)
    else
      @moesif_helpers.log_debug 'Content Encoding is of type other than gzip, returning nil'
      nil
    end
  rescue StandardError => e
    @moesif_helpers.log_debug 'Error while decompressing the response body'
    @moesif_helpers.log_debug e.to_s
    nil
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
end
