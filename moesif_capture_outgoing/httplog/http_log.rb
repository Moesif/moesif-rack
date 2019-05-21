require 'net/http'
require 'rack'
require 'moesif_api'
require 'json'
require 'base64'

module MoesifCaptureOutgoing

  class << self

    def start_capture_outgoing(options)
      @moesif_options = options
      if not @moesif_options['application_id']
        raise 'application_id required for Moesif Middleware'
      end
      @api_client = MoesifApi::MoesifAPIClient.new(@moesif_options['application_id'])
      @api_controller = @api_client.api
      @debug = @moesif_options['debug']
      @get_metadata_outgoing = @moesif_options['get_metadata_outgoing']
      @identify_user_outgoing = @moesif_options['identify_user_outgoing']
      @identify_session_outgoing = @moesif_options['identify_session_outgoing']
      @skip_outgoing = options['skip_outgoing']
      @mask_data_outgoing = options['mask_data_outgoing']
    end

    def call (url, request, request_time, response, response_time)
      send_moesif_event(url, request, request_time, response, response_time)
    end
    
    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      body = body.inject("") { |i, a| i << a } if body.respond_to?(:each)
      body.to_s
    end

    def transform_response_code(response_code_name)
      Rack::Utils::HTTP_STATUS_CODES.detect { |_k, v| v.to_s.casecmp(response_code_name.to_s).zero? }.first
    end

    def send_moesif_event(url, request, request_time, response, response_time)

      if url.downcase.include? "moesif"
        if @debug
          puts "Skip sending as it is moesif Event"
        end
      else 
        response.code = transform_response_code(response.code) if response.code.is_a?(Symbol)

        # Request Body
        req_body_string = request.body.nil? || request.body.empty? ? nil : request.body
        req_body_transfer_encoding = nil
        if req_body_string && req_body_string.length != 0
          begin
            req_body = JSON.parse(req_body_string)
          rescue
            req_body = Base64.encode64(req_body_string)
            req_body_transfer_encoding = 'base64'
          end
        end

        # Response Body and encoding
        rsp_body_string = get_response_body(response.body)
        rsp_body_transfer_encoding = nil

        if rsp_body_string && rsp_body_string.length != 0
          begin
            rsp_body = JSON.parse(rsp_body_string)
          rescue
            rsp_body = Base64.encode64(rsp_body_string)
            rsp_body_transfer_encoding = 'base64'
          end
        end

        # Event Request
        event_req = MoesifApi::EventRequestModel.new()
        event_req.time = request_time
        event_req.uri = url
        event_req.verb = request.method.to_s.upcase
        event_req.headers = request.each_header.collect.to_h
        event_req.api_version = nil
        event_req.body = req_body_string
        event_req.transfer_encoding = req_body_transfer_encoding

        # Event Response 
        event_rsp = MoesifApi::EventResponseModel.new()
        event_rsp.time = response_time
        event_rsp.status = response.code.to_i
        event_rsp.headers = response.each_header.collect.to_h
        event_rsp.body = rsp_body_string
        event_rsp.transfer_encoding = rsp_body_transfer_encoding

        # Prepare Event Model
        event_model = MoesifApi::EventModel.new()
        event_model.request = event_req
        event_model.response = event_rsp

        # Metadata for Outgoing Request
        if @get_metadata_outgoing
          if @debug
            puts "calling get_metadata_outgoing proc"
          end
          event_model.metadata = @get_metadata_outgoing.call(request, response)
        end

        # Identify User
        if @identify_user_outgoing
          if @debug
            puts "calling identify_user_outgoing proc"
          end
          event_model.user_id = @identify_user_outgoing.call(request, response)
        end

        # Session Token
        if @identify_session_outgoing
          if @debug
            puts "calling identify_session_outgoing proc"
          end
          event_model.session_token = @identify_session_outgoing.call(request, response)
        end

        # Skip Outgoing Request
        should_skip = false

        if @skip_outgoing
          if @skip_outgoing.call(request, response)
            should_skip = true;
          end
        end

        if !should_skip

          # Mask outgoing Event
          if @mask_data_outgoing
            if @debug
              puts "calling mask_data_outgoing proc"
            end
            event_model = @mask_data_outgoing.call(event_model)
          end

          # Send Event to Moesif
          begin
            if @debug
              puts 'Sending Outgoing Request Data to Moesif'
              puts event_model.to_json
            end
            @api_controller.create_event(event_model)
          rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
              puts "Unathorized accesss sending event to Moesif. Please verify your Application Id."
            end
            if @debug
              puts "Error sending event to Moesif, with status code: "
              puts e.response_code
            end
          end
        else 
          if @debug
            puts 'Skip sending outgoing request'
          end 
        end
      end
    end
  end
end
