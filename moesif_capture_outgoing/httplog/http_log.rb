require 'net/http'
require 'rack'
require 'moesif_api'
require 'json'
require 'base64'
require_relative '../../lib/moesif_rack/app_config'

module MoesifCaptureOutgoing
  class << self
    def start_capture_outgoing(options, app_config_manager, events_queue, moesif_helpers)
      @moesif_options = options
      raise 'application_id required for Moesif Middleware' unless @moesif_options['application_id']

      @api_client = MoesifApi::MoesifAPIClient.new(@moesif_options['application_id'])
      @api_controller = @api_client.api
      @debug = @moesif_options['debug']
      @get_metadata_outgoing = @moesif_options['get_metadata_outgoing']
      @identify_user_outgoing = @moesif_options['identify_user_outgoing']
      @identify_company_outgoing = @moesif_options['identify_company_outgoing']
      @identify_session_outgoing = @moesif_options['identify_session_outgoing']
      @skip_outgoing = options['skip_outgoing']
      @mask_data_outgoing = options['mask_data_outgoing']
      @log_body_outgoing = options.fetch('log_body_outgoing', true)

      @app_config = app_config_manager
      # @app_config and @events_queue should be shared instance from the middleware
      # so that we can use the same queue and same loaded @app_config
      @events_queue = events_queue
      @sampling_percentage = 100
      @last_updated_time = Time.now.utc
      @moesif_helpers = moesif_helpers
    end

    def should_capture_body
      @moesif_options.nil? ? false : @moesif_options['capture_outgoing_requests'] && @log_body_outgoing
    end

    def call(url, request, request_time, response, response_time, body_from_req_call, req_body_from_stream)
      send_moesif_event(url, request, request_time, response, response_time, body_from_req_call, req_body_from_stream)
    end

    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      body = body.inject('') { |i, a| i << a } if body.respond_to?(:each)
      body.to_s
    end

    def transform_response_code(response_code_name)
      Rack::Utils::HTTP_STATUS_CODES.detect { |_k, v| v.to_s.casecmp(response_code_name.to_s).zero? }.first
    end

    def send_moesif_event(url, request, request_time, response, response_time, body_from_req_call, req_body_from_stream)
      if url.downcase.include? 'moesif'
        @moesif_helpers.log_debug 'Skip adding to queue as it is moesif Event'
      else
        response.code = transform_response_code(response.code) if response.code.is_a?(Symbol)

        # Request headers
        req_headers = request.each_header.collect.to_h
        req_content_type = req_headers['content-type'].nil? ? req_headers['Content-Type'] : req_headers['content-type']

        # Request Body
        req_body_string = request.body.nil? || request.body.empty? ? body_from_req_call : request.body
        req_body_transfer_encoding = nil
        req_body = nil

        if @log_body_outgoing && (not req_content_type.nil?) && (req_content_type.downcase.include? 'multipart/form-data')
          @moesif_helpers.log_debug 'outgoing request is multipart, parsing req_body_from_stream'
          begin
            req_body = @moesif_helpers.parse_multipart(req_body_from_stream, req_content_type)
          rescue StandardError => e
            @moesif_helpers.log_debug 'outgoing request is multipart, but failed to process req_body_from_stream: ' + req_body_from_stream.to_s + e.to_s
            req_body = nil
          end
        elsif @log_body_outgoing && (req_body_string && req_body_string.length != 0)
          begin
            req_body = JSON.parse(req_body_string)
          rescue StandardError
            req_body = Base64.encode64(req_body_string)
            req_body_transfer_encoding = 'base64'
          end
        end

        # Response Body and encoding
        rsp_body_string = get_response_body(response.body)
        rsp_body_transfer_encoding = nil
        rsp_body = nil

        if @log_body_outgoing && (rsp_body_string && rsp_body_string.length != 0)
          begin
            rsp_body = JSON.parse(rsp_body_string)
          rescue StandardError
            rsp_body = Base64.encode64(rsp_body_string)
            rsp_body_transfer_encoding = 'base64'
          end
        end

        # Event Request
        event_req = MoesifApi::EventRequestModel.new
        event_req.time = request_time
        event_req.uri = url
        event_req.verb = request.method.to_s.upcase
        event_req.headers = req_headers
        event_req.api_version = nil

        event_req.body = req_body
        event_req.transfer_encoding = req_body_transfer_encoding

        # Event Response
        event_rsp = MoesifApi::EventResponseModel.new
        event_rsp.time = response_time
        event_rsp.status = response.code.to_i
        event_rsp.headers = response.each_header.collect.to_h
        event_rsp.body = rsp_body
        event_rsp.transfer_encoding = rsp_body_transfer_encoding

        # Prepare Event Model
        event_model = MoesifApi::EventModel.new
        event_model.request = event_req
        event_model.response = event_rsp
        event_model.direction = 'Outgoing'

        # Metadata for Outgoing Request
        if @get_metadata_outgoing
          puts 'calling get_metadata_outgoing proc' if @debug
          event_model.metadata = @get_metadata_outgoing.call(request, response)
        end

        # Identify User
        if @identify_user_outgoing
          puts 'calling identify_user_outgoing proc' if @debug
          event_model.user_id = @identify_user_outgoing.call(request, response)
        end

        # Identify Company
        if @identify_company_outgoing
          puts 'calling identify_company_outgoing proc' if @debug
          event_model.company_id = @identify_company_outgoing.call(request, response)
        end

        # Session Token
        if @identify_session_outgoing
          puts 'calling identify_session_outgoing proc' if @debug
          event_model.session_token = @identify_session_outgoing.call(request, response)
        end

        # Skip Outgoing Request
        should_skip = false

        should_skip = true if @skip_outgoing && @skip_outgoing.call(request, response)

        if !should_skip

          # Mask outgoing Event
          if @mask_data_outgoing
            puts 'calling mask_data_outgoing proc' if @debug
            event_model = @mask_data_outgoing.call(event_model)
          end

          # Send Event to Moesif
          begin
            @random_percentage = Random.rand(0.00..100.00)
            begin
              @sampling_percentage = @app_config.get_sampling_percentage(event_model, event_model.user_id,
                                                                         event_model.company_id)
            rescue StandardError => e
              if @debug
                puts 'Error while getting sampling percentage, assuming default behavior'
                puts e
              end
              @sampling_percentage = 100
            end

            if @sampling_percentage > @random_percentage
              event_model.weight = @app_config.calculate_weight(@sampling_percentage)
              @moesif_helpers.log_debug 'Adding Outgoing Request Data to Queue'
              @moesif_helpers.log_debug event_model.to_json

              # we put in the queue and format abot it.
              unless @events_queue.nil?
                @events_queue << event_model
                @moesif_helpers.log_debug 'Outgoing Event successfully added to event queue'
                return
              end
            else
              @moesif_helpers.log_debug('Skipped outgoing Event due to sampling percentage: ' + @sampling_percentage.to_s + ' and random percentage: ' + @random_percentage.to_s)
            end
          rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
              puts 'Unathorized accesss sending event to Moesif. Please verify your Application Id.'
            end
            if @debug
              puts 'Error sending event to Moesif, with status code: '
              puts e.response_code
            end
          rescue StandardError => e
            puts e if @debug
          end
        elsif @debug
          puts 'Skip sending outgoing request'
        end
      end
    end
  end
end
