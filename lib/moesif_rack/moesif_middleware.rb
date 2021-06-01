require 'moesif_api'
require 'json'
require 'time'
require 'base64'
require_relative './client_ip.rb'
require_relative './app_config.rb'
require_relative './update_user.rb'
require_relative './update_company.rb'
require_relative './helpers.rb'
require 'zlib'
require 'stringio'

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
      @app_config = AppConfig.new(@debug)
      @helpers = Helpers.new(@debug)
      @config = @app_config.get_config(@api_controller)
      @config_etag = nil
      @last_config_download_time = Time.now.utc
      @last_worker_run = Time.now.utc
      @config_dict = Hash.new
      @disable_transaction_id = options['disable_transaction_id'] || false
      @log_body = options.fetch('log_body', true)
      @batch_size = options['batch_size'] || 25
      @batch_max_time = options['batch_max_time'] || 2
      @events_queue = Queue.new
      @event_response_config_etag = nil
      start_worker()

      begin
        new_config = @app_config.get_config(@api_controller)
        if !new_config.nil?
          @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
        end
      rescue => exception
        @helpers.log_debug 'Error while parsing application configuration on initialization'
        @helpers.log_debug exception.to_s
      end
      @capture_outoing_requests = options['capture_outoing_requests']
      @capture_outgoing_requests = options['capture_outgoing_requests']
      if @capture_outoing_requests || @capture_outgoing_requests
        @helpers.log_debug 'Start Capturing outgoing requests'
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

    def start_with_json(body)
      body.start_with?('{') || body.start_with?('[')
    end

    def decompress_body(body)
      Zlib::GzipReader.new(StringIO.new(body)).read
    end

    def transform_headers(headers)
      Hash[headers.map { |k, v| [k.downcase, v]}]
    end

    def base64_encode_body(body)
      return Base64.encode64(body), 'base64'
    end

    def @helpers.log_debug(message)
      if @debug
        puts("#{Time.now.to_s} [Moesif Middleware] PID #{Process.pid} TID #{Thread.current.object_id} #{message}")
      end
    end

    def parse_body(body, headers)
      begin
        if (body.instance_of?(Hash) || body.instance_of?(Array))
          parsed_body = body
          transfer_encoding = 'json'
        elsif start_with_json(body)
          parsed_body = JSON.parse(body)
          transfer_encoding = 'json'
        elsif headers.key?('content-encoding') && ((headers['content-encoding'].downcase).include? "gzip")
          uncompressed_string = decompress_body(body)
          parsed_body, transfer_encoding = base64_encode_body(uncompressed_string)
        else
          parsed_body, transfer_encoding = base64_encode_body(body)
        end
      rescue
        parsed_body, transfer_encoding = base64_encode_body(body)
      end
      return parsed_body, transfer_encoding
    end

    def start_worker
      Thread::new do
        @last_worker_run = Time.now.utc
        loop do
          begin
            until @events_queue.empty? do
                batch_events = []
                until batch_events.size == @batch_size || @events_queue.empty? do 
                  batch_events << @events_queue.pop
                end 
                @helpers.log_debug("Sending #{batch_events.size.to_s} events to Moesif")
                event_api_response =  @api_controller.create_events_batch(batch_events)
                @event_response_config_etag = event_api_response[:x_moesif_config_etag]
                @helpers.log_debug(event_api_response.to_s)
                @helpers.log_debug("Events successfully sent to Moesif")
            end
            
            if @events_queue.empty?
              @helpers.log_debug("No events to read from the queue")
            end
  
            sleep @batch_max_time
          rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
              puts "Unathorized accesss sending event to Moesif. Please verify your Application Id."
              @helpers.log_debug(e.to_s)
            end
            @helpers.log_debug("Error sending event to Moesif, with status code #{e.response_code.to_s}")
          rescue => e
            @helpers.log_debug(e.to_s)
          end
        end
      end
    end

    def call env
      start_time = Time.now.utc.iso8601

      @helpers.log_debug('Calling Moesif middleware')

      status, headers, body = @app.call env
      end_time = Time.now.utc.iso8601

      process_send = lambda do
        req = Rack::Request.new(env)
        complex_copy = env.dup

        req_headers = {}
        complex_copy.select {|k,v| k.start_with?('HTTP_', 'CONTENT_') }.each do |key, val|
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
            req_body, req_body_transfer_encoding = parse_body(req_body_string, transform_headers(req_headers))
          end
        end

        rsp_headers = headers.dup

        rsp_body_string = get_response_body(body);
        rsp_body_transfer_encoding = nil
        rsp_body = nil

        if @log_body
          if rsp_body_string && rsp_body_string.length != 0
            rsp_body, rsp_body_transfer_encoding = parse_body(rsp_body_string, transform_headers(rsp_headers))
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
          @helpers.log_debug "calling identify user proc"
          event_model.user_id = @identify_user.call(env, headers, body)
        end

        if @identify_company
          @helpers.log_debug "calling identify company proc"
          event_model.company_id = @identify_company.call(env, headers, body)
        end

        if @get_metadata
          @helpers.log_debug "calling get_metadata proc"
          event_model.metadata = @get_metadata.call(env, headers, body)
        end

        if @identify_session
          @helpers.log_debug "calling identify session proc"
          event_model.session_token = @identify_session.call(env, headers, body)
        end
        if @mask_data
          @helpers.log_debug "calling mask_data proc"
          event_model = @mask_data.call(event_model)
        end

        @helpers.log_debug "sending data to moesif"
        @helpers.log_debug event_model.to_json
        # Perform the API call through the SDK function
        begin
          random_percentage  = Random.rand(0.00..100.00)

          begin 
            sampling_percentage = @app_config.get_sampling_percentage(@config, event_model.user_id, event_model.company_id)
            @helpers.log_debug "Using sample rate #{sampling_percentage}"
          rescue => exception
            @helpers.log_debug 'Error while getting sampling percentage, assuming default behavior'
            @helpers.log_debug exception.to_s
            sampling_percentage = 100
          end

          if sampling_percentage > random_percentage 
            event_model.weight = @app_config.calculate_weight(sampling_percentage)
            # Add Event to the queue
            @events_queue << event_model
            @helpers.log_debug("Event added to the queue ")
            if Time.now.utc > (@last_worker_run + 60)
              start_worker()
            end

            if !@event_response_config_etag.nil? && !@config_etag.nil? && @config_etag != @event_response_config_etag && Time.now.utc > (@last_config_download_time + 300)
              begin 
                new_config = @app_config.get_config(@api_controller)
                if !new_config.nil?
                  @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
                end

              rescue => exception
                @helpers.log_debug 'Error while updating the application configuration'
                @helpers.log_debug exception.to_s
              end
            end
          else
            @helpers.log_debug("Skipped Event due to sampling percentage: " + sampling_percentage.to_s + " and random percentage: " + random_percentage .to_s)
          end
        rescue => exception
          @helpers.log_debug "Error adding event to the queue "
          @helpers.log_debug exception.to_s
        end

      end

      should_skip = false

      if @skip
        if @skip.call(env, headers, body)
          should_skip = true;
        end
      end

      if !should_skip
        begin 
          process_send.call
        rescue => exception
          @helpers.log_debug 'Error while logging event - '
          @helpers.log_debug exception.to_s
        end
      end

      [status, headers, body]
    end

    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      if (body.instance_of?(Hash) || body.instance_of?(Array))
        return body
      end
      body = body.inject("") { |i, a| i << a } if (body.respond_to?(:each) && body.respond_to?(:inject))
      body.to_s
    end

  end
end
