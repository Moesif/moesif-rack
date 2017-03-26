require 'moesif_api'
require 'json'
require 'time'
require 'base64'

module MoesifRack

  class MoesifMiddleware
    def initialize app, options = {}
      @app = app
      if not options['application_id']
        raise 'application_id requird for Moesif Middleware'
      end
      @api_client = MoesifApi::MoesifAPIClient.new(options['application_id'])
      @api_controller = @api_client.api

      @api_version = options['api_version']
      @identify_user = options['identify_user']
      @identify_session = options['identify_session']
      @mask_data = options['mask_data']
      @skip = options['skip']
      @debug = options['debug']
    end

    def call env
      start_time = Time.now.utc.iso8601

      if @debug
        puts 'inside moesif middleware'
      end

      status, headers, body = @app.call env
      end_time = Time.now.utc.iso8601

      process_send = lambda do
        req = Rack::Request.new(env)
        complex_copy = env.dup

        req_headers = {}
        complex_copy.select {|k,v| k.start_with? 'HTTP_'}.each do |key, val|
          req_headers[key.sub(/^HTTP_/, '')] = val
        end

        req_body_string = req.body.read
        req.body.rewind
        req_body_transfer_encoding = nil

        if req_body_string && req_body_string.length != 0
          begin
            req_body = JSON.parse(req_body_string)
          rescue
            req_body = Base64.encode64(req_body_string)
            req_body_transfer_encoding = 'base64'
          end
        end

        rsp_headers = headers.dup

        rsp_body_string = get_response_body(body);
        rsp_body_transfer_encoding = nil

        if rsp_body_string && rsp_body_string.length != 0
          begin
            rsp_body = JSON.parse(rsp_body_string)
          rescue
            rsp_body = Base64.encode64(rsp_body_string)
            rsp_body_transfer_encoding = 'base64'
          end
        end

        event_req = MoesifApi::EventRequestModel.new()
        event_req.time = start_time
        event_req.uri = req.url
        event_req.verb = req.request_method

        if @api_version
          event_req.api_version = @api_version
        end
        event_req.ip_address = req.ip
        event_req.headers = req_headers
        event_req.body = req_body
        event_req.transfer_encoding = req_body_transfer_encoding

        event_rsp = MoesifApi::EventResponseModel.new()
        event_rsp.time = end_time
        event_rsp.status = status
        event_rsp.headers = rsp_headers
        event_rsp.body = rsp_body
        event_rsp.transfer_encoding = rsp_body_transfer_encoding

        event_model = MoesifApi::EventModel.new()
        event_model.request = event_req
        event_model.response = event_rsp
        if @identify_user
          if @debug
            puts "calling identify user proc"
          end
          event_model.user_id = @identify_user.call(env, headers, body)
        end
        if @identify_session
          if @debug
            puts "calling identify session proc"
          end
          event_model.session_token = @identify_session.call(env, headers, body)
        end
        if @mask_data
          if @debug
            puts "calling mask_data proc"
          end
          event_model = @mask_data.call(event_model)
        end

        if @debug
          puts "sending data to moesif"
          puts event_model.to_json
        end
        # Perform the API call through the SDK function
        @api_controller.create_event(event_model)

      end

      should_skip = false

      if @skip
        if @skip.call(env, headers, body)
          should_skip = true;
        end
      end

      if !should_skip
        if @debug
          process_send.call
        else
          Thread.start(&process_send)
        end
      end

      [status, headers, body]
    end

    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      body = body.inject("") { |i, a| i << a } if body.respond_to?(:each)
      body.to_s
    end

  end
end
