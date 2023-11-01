require 'time'

module Net
  class HTTP
    alias orig_request request unless method_defined?(:orig_request)

    def request(request, body = nil, &block)
      # Request Start Time
      request_time = Time.now.utc.iso8601(3)
      # URL
      url = "https://#{@address}#{request.path}"

      if (not request.body_stream.nil?) && MoesifCaptureOutgoing.should_capture_body
        req_body_from_stream = request.body_stream.read
        request.body_stream.rewind
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
