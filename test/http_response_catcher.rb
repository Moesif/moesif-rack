

class HttpResponseCatcher < MoesifApi::HttpCallBack
  attr_accessor :response

  def on_before_request(request)
  end

  # Catching the response
  def on_after_response(context)
    @response = context.response
  end
end



