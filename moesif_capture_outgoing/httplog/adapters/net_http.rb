require 'time'

module Net
    class HTTP
      alias orig_request request unless method_defined?(:orig_request)
  
      def request(request, body = nil, &block)

        # Request Start Time
        request_time = Time.now.utc.iso8601
        
        # URL
        url = "https://#{@address}#{request.path}"

        # Response
        @response = orig_request(request, body, &block)

        # Response Time
        response_time = Time.now.utc.iso8601
  
        # Log Event to Moesif
        if started?
            MoesifCaptureOutgoing.call(url, request, request_time, @response, response_time)
        end
  
        @response
      end
    end
  end
