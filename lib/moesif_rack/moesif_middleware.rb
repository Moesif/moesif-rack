require 'moesif_api'
require 'json'
require 'time'
require 'base64'
require 'zlib'
require 'stringio'
require 'rack'
require_relative './client_ip'
require_relative './app_config'
require_relative './update_user'
require_relative './update_company'
require_relative './moesif_helpers'
require_relative './governance_rules'

module MoesifRack
  class MoesifMiddleware
    def initialize(app, options = {})
      @app = app
      raise 'application_id required for Moesif Middleware' unless options['application_id']

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
      @moesif_helpers = MoesifHelpers.new(@debug)
      # @config = @app_config.get_config(@api_controller)
      @config_etag = nil
      @last_config_download_time = Time.now.utc
      @config_dict = {}
      @disable_transaction_id = options['disable_transaction_id'] || false
      @log_body = options.fetch('log_body', true)
      @batch_size = options['batch_size'] || 200
      @event_queue_size = options['event_queue_size'] || 1000
      @batch_max_time = options['batch_max_time'] || 2
      @events_queue = Queue.new
      @event_response_config_etag = nil
      @governance = GovernanceRules.new(@debug)

      # start the worker and Update the last worker run
      @last_worker_run = Time.now.utc
      start_worker

      begin
        new_config = @app_config.get_config(@api_controller)
        unless new_config.nil?
          @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
        end
        @governance.load_rules(@api_controller)
      rescue StandardError => e
        @moesif_helpers.log_debug 'Error while parsing application configuration on initialization'
        @moesif_helpers.log_debug e.to_s
      end
      @capture_outoing_requests = options['capture_outoing_requests']
      @capture_outgoing_requests = options['capture_outgoing_requests']
      return unless @capture_outoing_requests || @capture_outgoing_requests

      @moesif_helpers.log_debug 'Start Capturing outgoing requests'
      require_relative '../../moesif_capture_outgoing/httplog'
      MoesifCaptureOutgoing.start_capture_outgoing(options)
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
      Hash[headers.map { |k, v| [k.downcase, v] }]
    end

    def base64_encode_body(body)
      [Base64.encode64(body), 'base64']
    end

    def @moesif_helpers.log_debug(message)
      return unless @debug

      puts("#{Time.now} [Moesif Middleware] PID #{Process.pid} TID #{Thread.current.object_id} #{message}")
    end

    def parse_multipart(multipart_form_data, content_type)
      @moesif_helpers.log_debug("try to parse multiple part #{content_type}")

      sanitized_multipart_form_data = multipart_form_data.gsub(/\r?\n/, "\r\n")

      io = StringIO.new(sanitized_multipart_form_data)
      tempfile = Rack::Multipart::Parser::TEMPFILE_FACTORY
      bufsize = Rack::Multipart::Parser::BUFSIZE
      query_parser = Rack::Utils.default_query_parser
      result = Rack::Multipart::Parser.parse(io, sanitized_multipart_form_data.length, content_type, tempfile, bufsize,
                                             query_parser)

      @moesif_helpers.log_debug('multipart parse result')
      @moesif_helpers.log_debug(result.inspect)

      # this is a hash shold be treated as JSON down the road.
      result.params
    end

    def parse_body(body, headers)
      begin
        if body.instance_of?(Hash) || body.instance_of?(Array)
          parsed_body = body
          transfer_encoding = 'json'
        elsif start_with_json(body)
          parsed_body = JSON.parse(body)
          transfer_encoding = 'json'
        elsif headers.key?('content-type') && (headers['content-type'].downcase.include? 'multipart/form-data')
          parsed_body = parse_multipart(body, headers['content-type'])
          transfer_encoding = 'json'
        elsif headers.key?('content-encoding') && (headers['content-encoding'].downcase.include? 'gzip')
          uncompressed_string = decompress_body(body)
          parsed_body, transfer_encoding = base64_encode_body(uncompressed_string)
        else
          parsed_body, transfer_encoding = base64_encode_body(body)
        end
      rescue StandardError
        parsed_body, transfer_encoding = base64_encode_body(body)
      end
      [parsed_body, transfer_encoding]
    end

    def start_worker
      Thread.new do
        loop do
          # Update the last worker run, in case the events_queue is empty
          @last_worker_run = Time.now.utc
          begin
            until @events_queue.empty?
              # Update the last worker run in case sending events take more than 60 seconds
              @last_worker_run = Time.now.utc
              # Populate the batch events from queue
              batch_events = []
              batch_events << @events_queue.pop until batch_events.size == @batch_size || @events_queue.empty?
              @moesif_helpers.log_debug("Sending #{batch_events.size} events to Moesif")
              event_api_response = @api_controller.create_events_batch(batch_events)
              @event_response_config_etag = event_api_response[:x_moesif_config_etag]
              @moesif_helpers.log_debug(event_api_response.to_s)
              @moesif_helpers.log_debug('Events successfully sent to Moesif')
            end

            @moesif_helpers.log_debug('No events to read from the queue') if @events_queue.empty?

            sleep @batch_max_time
          rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
              puts 'Unathorized accesss sending event to Moesif. Please verify your Application Id.'
              @moesif_helpers.log_debug(e.to_s)
            end
            @moesif_helpers.log_debug("Error sending event to Moesif, with status code #{e.response_code}")
          rescue StandardError => e
            @moesif_helpers.log_debug(e.to_s)
          end
        end
      end
    end

    def call(env)
      start_time = Time.now.utc.iso8601(3)

      @moesif_helpers.log_debug('Calling Moesif middleware')

      status, headers, body = @app.call env
      end_time = Time.now.utc.iso8601(3)

      make_event_model = lambda do
        req = Rack::Request.new(env)
        complex_copy = env.dup

        # Filter hash to only have keys of type string
        complex_copy = complex_copy.select { |k, _v| k.is_a? String }

        req_headers = {}
        complex_copy.select { |k, _v| k.start_with?('HTTP_', 'CONTENT_') }.each do |key, val|
          new_key = key.sub(/^HTTP_/, '')
          new_key = new_key.sub('_', '-')
          req_headers[new_key] = val
        end

        # rewind first in case someone else already read the body
        req.body.rewind
        req_body_string = req.body.read
        req.body.rewind
        req_body_transfer_encoding = nil
        req_body = nil

        if @log_body && (req_body_string && req_body_string.length != 0)
          req_body, req_body_transfer_encoding = parse_body(req_body_string,
                                                            transform_headers(req_headers))
        end

        rsp_headers = headers.dup

        rsp_body_string = get_response_body(body)
        rsp_body_transfer_encoding = nil
        rsp_body = nil

        if @log_body && (rsp_body_string && rsp_body_string.length != 0)
          rsp_body, rsp_body_transfer_encoding = parse_body(rsp_body_string,
                                                            transform_headers(rsp_headers))
        end

        event_req = MoesifApi::EventRequestModel.new
        event_req.time = start_time
        event_req.uri = req.url
        event_req.verb = req.request_method

        event_req.api_version = @api_version if @api_version

        # Add Transaction Id to the Request Header
        unless @disable_transaction_id
          req_trans_id = req_headers['X-MOESIF_TRANSACTION_ID']
          if !req_trans_id.nil?
            transaction_id = req_trans_id
            transaction_id = SecureRandom.uuid if transaction_id.strip.empty?
          else
            transaction_id = SecureRandom.uuid
          end
          # Add Transaction Id to Request Header
          req_headers['X-Moesif-Transaction-Id'] = transaction_id
          # Filter out the old key as HTTP Headers case are not preserved
          req_headers = req_headers.except('X-MOESIF_TRANSACTION_ID') if req_headers.key?('X-MOESIF_TRANSACTION_ID')
        end

        # Add Transaction Id to the Response Header
        rsp_headers['X-Moesif-Transaction-Id'] = transaction_id unless transaction_id.nil?

        # Add Transaction Id to the Repsonse Header sent to the client
        headers['X-Moesif-Transaction-Id'] = transaction_id unless transaction_id.nil?

        event_req.ip_address = get_client_address(req.env)
        event_req.headers = req_headers
        event_req.body = req_body
        event_req.transfer_encoding = req_body_transfer_encoding

        event_rsp = MoesifApi::EventResponseModel.new
        event_rsp.time = end_time
        event_rsp.status = status
        event_rsp.headers = rsp_headers
        event_rsp.body = rsp_body
        event_rsp.transfer_encoding = rsp_body_transfer_encoding

        _event_model = MoesifApi::EventModel.new
        _event_model.request = event_req
        _event_model.response = event_rsp
        _event_model.direction = 'Incoming'

        if @identify_user
          @moesif_helpers.log_debug 'calling identify user proc'
          _event_model.user_id = @identify_user.call(env, headers, body)
        end

        if @identify_company
          @moesif_helpers.log_debug 'calling identify company proc'
          _event_model.company_id = @identify_company.call(env, headers, body)
        end

        if @get_metadata
          @moesif_helpers.log_debug 'calling get_metadata proc'
          _event_model.metadata = @get_metadata.call(env, headers, body)
        end

        if @identify_session
          @moesif_helpers.log_debug 'calling identify session proc'
          _event_model.session_token = @identify_session.call(env, headers, body)
        end
        if @mask_data
          @moesif_helpers.log_debug 'calling mask_data proc'
          _event_model = @mask_data.call(_event_model)
        end

        return _event_model
      rescue StandardError => e
        @moesif_helpers.log_debug 'Error making event model'
        @moesif_helpers.log_debug e.to_s
      end

      process_send = lambda do |_event_mode|
        @moesif_helpers.log_debug 'sending data to moesif'
        @moesif_helpers.log_debug _event_model.to_json
        # Perform the API call through the SDK function
        begin
          random_percentage = Random.rand(0.00..100.00)

          begin
            sampling_percentage = @app_config.get_sampling_percentage(_event_model, @config, _event_model.user_id,
                                                                      _event_model.company_id)
            @moesif_helpers.log_debug "Using sample rate #{sampling_percentage}"
          rescue StandardError => e
            @moesif_helpers.log_debug 'Error while getting sampling percentage, assuming default behavior'
            @moesif_helpers.log_debug e.to_s
            sampling_percentage = 100
          end

          if sampling_percentage > random_percentage
            _event_model.weight = @app_config.calculate_weight(sampling_percentage)
            # Add Event to the queue
            if @events_queue.size >= @event_queue_size
              @moesif_helpers.log_debug("Skipped Event due to events_queue size [#{@events_queue.size}] is over max #{@event_queue_size} ")
            else
              @events_queue << _event_model
              @moesif_helpers.log_debug('Event added to the queue ')
            end

            start_worker if Time.now.utc > (@last_worker_run + 60)

            if !@event_response_config_etag.nil? && !@config_etag.nil? && @config_etag != @event_response_config_etag && Time.now.utc > (@last_config_download_time + 300)
              begin
                new_config = @app_config.get_config(@api_controller)
                unless new_config.nil?
                  @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
                end
                @governance.reload_rules_if_needed(@api_controller)
              rescue StandardError => e
                @moesif_helpers.log_debug 'Error while updating the application configuration'
                @moesif_helpers.log_debug e.to_s
              end
            end
          else
            @moesif_helpers.log_debug('Skipped Event due to sampling percentage: ' + sampling_percentage.to_s + ' and random percentage: ' + random_percentage.to_s)
          end
        rescue StandardError => e
          @moesif_helpers.log_debug 'Error adding event to the queue '
          @moesif_helpers.log_debug e.to_s
        end
      end

      should_skip = false

      should_skip = true if @skip && @skip.call(env, headers, body)

      should_govern = true

      event_model = make_event_model.call if !should_skip || should_govern

      if should_govern
        # now we can do govern based on
        # override_response = govern(env, event_model)
        # return override_response if override_response
        new_response = @governance.govern_request(@config, env, event_model, status, headers, body)

        # update the event model
        if new_response
          event_model.response.status = new_response.fetch(:status, status)
          event_model.response.header = new_response.fetch(:headers, headers).dup
          replaced_body = new_response.fetch(:body, rsp_body)
          event_model.blocked_by = new_response.fetch(:block_rule_id, nil)
          if !event_model.blocked_by.nil?
            event_model.response.body = replaced_body
            # replaced body is always json should not be transfer encoding needed.
            event_model.transfer_encoding = nil
          end
        end
      end

      if !should_skip
        begin
          process_send.call(event_model)
        rescue StandardError => e
          @moesif_helpers.log_debug 'Error while logging event - '
          @moesif_helpers.log_debug e.to_s
          @moesif_helpers.log_debug e.backtrace
        end
      else
        @moesif_helpers.log_debug 'Skipped Event using should_skip configuration option.'
      end

      unless new_response.nil?
        return [new_response.fetch(:status, status), new_response.fetch(:headers, headers),
                new_response.fetch(:body, body)]
      end

      [status, headers, body]
    end

    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      return body if body.instance_of?(Hash) || body.instance_of?(Array)

      body = body.inject('') { |i, a| i << a } if body.respond_to?(:each) && body.respond_to?(:inject)
      body.to_s
    end
  end
end
