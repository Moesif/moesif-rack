require 'moesif_api'
require 'json'
require 'time'
require 'base64'
require_relative './client_ip.rb'
require_relative './app_config.rb'
require_relative './update_user.rb'
require_relative './update_company.rb'

module MoesifRack

  class MoesifMiddleware
    def initialize app, options = {}
      @app = app
      if not options['application_id']
        raise 'application_id required for Moesif Middleware'
      end
      @api_client = MoesifApi::MoesifAPIClient.new(options['application_id'])
      @api_controller = @api_client.api

      @api_version = options['api_version']
      @identify_user = options['identify_user']
      @identify_company = options['identify_company']
      @get_metadata = options['get_metadata']
      @identify_session = options['identify_session']
      @mask_data = options['mask_data']
      @skip = options['skip']
      @debug = options['debug']
      @app_config = AppConfig.new
      @config = @app_config.get_config(@api_controller, @debug)
      @config_etag = nil
      @sampling_percentage = 100
      @last_updated_time = Time.now.utc
      @config_dict = Hash.new
      @disable_transaction_id = options['disable_transaction_id'] || false
      @log_body = options.fetch('log_body', true)
      begin
        if !@config.nil?
          @config_etag, @sampling_percentage, @last_updated_time = @app_config.parse_configuration(@config, @debug)
        end
      rescue => exception
        if @debug
          puts 'Error while parsing application configuration on initialization'
          puts exception.to_s
        end
      end
      @capture_outoing_requests = options['capture_outoing_requests']
      @capture_outgoing_requests = options['capture_outgoing_requests']
      if @capture_outoing_requests || @capture_outgoing_requests
        if @debug
          puts 'Start Capturing outgoing requests'
        end
        require_relative '../../moesif_capture_outgoing/httplog.rb'
        MoesifCaptureOutgoing.start_capture_outgoing(options)
      end
    end

    def update_user(user_profile)
      UserHelper.new.update_user(@api_controller, @debug, user_profile)
    end

    def update_users_batch(user_profiles)
      UserHelper.new.update_users_batch(@api_controller, @debug, user_profiles)
    end

    def update_company(company_profile)
      CompanyHelper.new.update_company(@api_controller, @debug, company_profile)
    end

    def update_companies_batch(company_profiles)
      CompanyHelper.new.update_companies_batch(@api_controller, @debug, company_profiles)
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
        req_body = nil

        if @log_body
          if req_body_string && req_body_string.length != 0
            begin
              req_body = JSON.parse(req_body_string)
            rescue
              req_body = Base64.encode64(req_body_string)
              req_body_transfer_encoding = 'base64'
            end
          end
        end

        rsp_headers = headers.dup

        rsp_body_string = get_response_body(body);
        rsp_body_transfer_encoding = nil
        rsp_body = nil

        if @log_body
          if rsp_body_string && rsp_body_string.length != 0
            begin
              rsp_body = JSON.parse(rsp_body_string)
            rescue
              rsp_body = Base64.encode64(rsp_body_string)
              rsp_body_transfer_encoding = 'base64'
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

        # Add Transaction Id to the Request Header
        if !@disable_transaction_id
          req_trans_id = req_headers["X-MOESIF_TRANSACTION_ID"]
          if !req_trans_id.nil?
            transaction_id = req_trans_id
            if transaction_id.strip.empty?
              transaction_id = SecureRandom.uuid
            end
          else
            transaction_id = SecureRandom.uuid
          end
          # Add Transaction Id to Request Header
          req_headers["X-Moesif-Transaction-Id"] = transaction_id
          # Filter out the old key as HTTP Headers case are not preserved
          if req_headers.key?("X-MOESIF_TRANSACTION_ID")
            req_headers = req_headers.except("X-MOESIF_TRANSACTION_ID")
          end
        end

        # Add Transaction Id to the Response Header
        if !transaction_id.nil?  
          rsp_headers["X-Moesif-Transaction-Id"] = transaction_id
        end

        # Add Transaction Id to the Repsonse Header sent to the client
        if !transaction_id.nil?  
          headers["X-Moesif-Transaction-Id"] = transaction_id
        end

        event_req.ip_address = get_client_address(req.env)
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
        event_model.direction = "Incoming"
        
        if @identify_user
          if @debug
            puts "calling identify user proc"
          end
          event_model.user_id = @identify_user.call(env, headers, body)
        end

        if @identify_company
          if @debug
            puts "calling identify company proc"
          end
          event_model.company_id = @identify_company.call(env, headers, body)
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

          begin 
            @sampling_percentage = @app_config.get_sampling_percentage(@config, event_model.user_id, event_model.company_id, @debug)
          rescue => exception
            if @debug
              puts 'Error while getting sampling percentage, assuming default behavior'
              puts exception.to_s
            end
            @sampling_percentage = 100
          end

          if @sampling_percentage > @random_percentage
            event_api_response = @api_controller.create_event(event_model)
            event_response_config_etag = event_api_response[:x_moesif_config_etag]

            if !event_response_config_etag.nil? && !@config_etag.nil? && @config_etag != event_response_config_etag && Time.now.utc > @last_updated_time + 300
              begin 
                @config = @app_config.get_config(@api_controller, @debug)
                @config_etag, @sampling_percentage, @last_updated_time = @app_config.parse_configuration(@config, @debug)
              rescue => exception
                if @debug
                  puts 'Error while updating the application configuration'
                  puts exception.to_s
                end    
              end
            end
            if @debug
              puts("Event successfully sent to Moesif")
            end
          else
            if @debug
              puts("Skipped Event due to sampling percentage: " + @sampling_percentage.to_s + " and random percentage: " + @random_percentage.to_s)
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
      body = body.inject("") { |i, a| i << a } if (body.respond_to?(:each) && body.respond_to?(:inject))
      body.to_s
    end

  end
end
