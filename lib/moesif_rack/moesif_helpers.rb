require 'time'

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

end
