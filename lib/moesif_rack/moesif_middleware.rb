require 'moesif_api'
require 'json'
require 'time'

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

        if req_body_string && req_body_string.length != 0
          begin
            req_body = JSON.parse(req_body_string)
          rescue
            req_body = {
              'moesif_error' => {
                'code': 'json_parse_error',
                'src': 'moesif-rack',
                'msg' => ['Body is not a JSON Object or JSON Array'],
                'args' => [req_body_string]
              }
            }
          end
        end

        rsp_headers = headers.dup

        content_type = rsp_headers['Content-Type'];

        if body && body.body
          begin
            rsp_body = JSON.parse(body.body)
          rescue
            if content_type && (content_type.include? "json")
              rsp_body = {
                'moesif_error' => {
                  'code': 'json_parse_error',
                  'src': 'moesif-rack',
                  'msg' => ['Body is not a JSON Object or JSON Array'],
                  'args' => [body.body]
                }
              }
            end
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

        event_rsp = MoesifApi::EventResponseModel.new()
        event_rsp.time = end_time
        event_rsp.status = status
        event_rsp.headers = rsp_headers
        event_rsp.body = rsp_body

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
  end
end
