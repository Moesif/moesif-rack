require 'time'

module Net
  class HTTP
    alias orig_request request unless method_defined?(:orig_request)

    def extract_body_from_body_stream(body_stream)
      begin
        result = nil
        if body_stream.respond_to?(:rewind) and body_stream.respond_to?(:read)
          result = body_stream.read
          body_stream.rewind
        elsif body_stream.respond_to?(:to_s)
          result = body_stream.to_s
          if body_stream.respond_to?(:seek)
             # if stream respond to seek let's reset seek to 0
             body_stream.seek(0)
          end
        end
        result
      rescue StandardError => e
        # do nothig for now
        return nil
      end
    end

    def request(request, body = nil, &block)
      # Request Start Time
      request_time = Time.now.utc.iso8601(3)
      # URL
      url = "https://#{@address}#{request.path}"

      if (not request.body_stream.nil?) && MoesifCaptureOutgoing.should_capture_body
        req_body_from_stream = extract_body_from_body_stream(request.body_stream)
      end

      # Response
      @response = orig_request(request, body, &block)

      # Response Time
      response_time = Time.now.utc.iso8601(3)

      # Log Event to Moesif
      body_from_req_call = body
      MoesifCaptureOutgoing.call(url, request, request_time, @response, response_time, body_from_req_call, req_body_from_stream) if started?

      @response
    end
  end
end
