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
      @get_metadata = options['get_metadata']
      @identify_session = options['identify_session']
      @mask_data = options['mask_data']
      @skip = options['skip']
      @debug = options['debug']
      @config_dict = Hash.new
      @sampling_percentage = get_config(nil)
      if not @sampling_percentage.is_a? Numeric
        raise "Sampling Percentage should be a number"
      end
    end

    def get_config(cached_config_etag)
      sample_rate = 100
      begin
        # Calling the api
        config_api_response = @api_controller.get_app_config()
        # Fetch the response ETag
        response_config_etag = JSON.parse( config_api_response.to_json )["headers"]["x_moesif_config_etag"]
        # Remove ETag from the global dict if exist
        if !cached_config_etag.nil? && @config_dict.key?(cached_config_etag)
            @config_dict.delete(cached_config_etag)
        end
        # Fetch the response body
        @config_dict[response_config_etag] = JSON.parse(JSON.parse( config_api_response.to_json )["raw_body"])
        # 
        app_config = @config_dict[response_config_etag]
        # Fetch the sample rate
        if !app_config.nil?
          sample_rate = app_config.fetch("sample_rate", 100)
        end
        # Set the last updated time
        @last_updated_time = Time.now.utc
        rescue
          # Set the last updated time
          @last_updated_time = Time.now.utc
      end
      # Return the sample rate
      return sample_rate
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
          new_key = key.sub(/^HTTP_/, '')
          new_key = new_key.sub('_', '-')
          req_headers[new_key] = val
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

        if @get_metadata
          if @debug
            puts "calling get_metadata proc"
          end
          event_model.metadata = @get_metadata.call(env, headers, body)
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
        begin
          @random_percentage = Random.rand(0.00..100.00)
          if @sampling_percentage > @random_percentage
            event_api_response = @api_controller.create_event(event_model)
            cached_config_etag = @config_dict.keys[0]
            event_response_config_etag = event_api_response[:x_moesif_config_etag]

            if !event_response_config_etag.nil? && cached_config_etag != event_response_config_etag && Time.now.utc > @last_updated_time + 30
              @sampling_percentage = get_config(cached_config_etag)
            end
            if @debug
              puts("Event successfully sent to Moesif")
            end
          else
            if @debug
              puts("Skipped Event due to sampling percentage: " + @sampling_percentage.to_s + " and random percentage: " + @random_percentage.to_s);
            end
          end
        rescue MoesifApi::APIException => e
          if e.response_code.between?(401, 403)
            puts "Unathorized accesss sending event to Moesif. Please verify your Application Id."
          end
          if @debug
            puts "Error sending event to Moesif, with status code: "
            puts e.response_code
          end
        end

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
