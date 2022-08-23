require 'moesif_api'
require 'json'
require 'time'
require 'zlib'
require 'stringio'
require_relative './moesif_helpers.rb'
require_relative './regex_config_helper.rb'

class AppConfig

    def initialize debug
        @debug = debug
        @moesif_helpers = MoesifHelpers.new(debug)
        @regex_config_helper = RegexConfigHelper.new(debug)
    end

    def get_config(api_controller)
        # Get Application Config
        begin 
            config_api_response = api_controller.get_app_config()
            @moesif_helpers.log_debug("new config downloaded")
            @moesif_helpers.log_debug(config_api_response.to_s)
            return config_api_response
        rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
                @moesif_helpers.log_debug 'Unauthorized access getting application configuration. Please check your Appplication Id.'
            end
            @moesif_helpers.log_debug 'Error getting application configuration, with status code:'
            @moesif_helpers.log_debug e.response_code
        rescue => e
            @moesif_helpers.log_debug e.to_s
        end
        rescue
    end

    def parse_configuration(config_api_response)
        # Parse configuration object and return Etag, sample rate and last updated time
        begin
            # Rails return gzipped compressed response body, so decompressing it and getting JSON response body
            response_body = decompress_gzip_body(config_api_response)
            @moesif_helpers.log_debug(response_body.to_s)

            # Check if response body is not nil
            if !response_body.nil? then 
                # Return Etag, sample rate and last updated time
                return response_body, config_api_response.headers[:x_moesif_config_etag], Time.now.utc
            else
                @moesif_helpers.log_debug 'Response body is nil, assuming default behavior'
                # Response body is nil, so assuming default behavior
                return nil, nil, Time.now.utc
            end
        rescue => exception
            @moesif_helpers.log_debug 'Error while parsing the configuration object, assuming default behavior'
            @moesif_helpers.log_debug exception.to_s
            # Assuming default behavior
            return nil, nil, Time.now.utc
        end
    end

    def get_sampling_percentage(event_model, config_api_response, user_id, company_id)
        # Get sampling percentage
        begin
            # Check if response body is not nil
            if !config_api_response.nil? then 
                @moesif_helpers.log_debug("Getting sample rate for user #{user_id} company #{company_id}")
                @moesif_helpers.log_debug(config_api_response.to_s)

                # Get Regex Sampling rate
                regex_config = config_api_response.fetch('regex_config', nil)

                if !regex_config.nil? and !event_model.nil?
                    config_mapping = @regex_config_helper.prepare_config_mapping(event_model)
                    regex_sample_rate = @regex_config_helper.fetch_sample_rate_on_regex_match(regex_config, config_mapping)
                    if !regex_sample_rate.nil?
                        return regex_sample_rate
                    end
                end

                # Get user sample rate object
                user_sample_rate = config_api_response.fetch('user_sample_rate', nil)

                # Get company sample rate object
                company_sample_rate = config_api_response.fetch('company_sample_rate', nil)

                # Get sample rate for the user if exist
                if !user_id.nil? && !user_sample_rate.nil? && user_sample_rate.key?(user_id)
                    return user_sample_rate.fetch(user_id)
                end

                # Get sample rate for the company if exist
                if !company_id.nil? && !company_sample_rate.nil? && company_sample_rate.key?(company_id)
                    return company_sample_rate.fetch(company_id)
                end

                # Return sample rate
                return config_api_response.fetch('sample_rate', 100)
            else 
                @moesif_helpers.log_debug 'Assuming default behavior as response body is nil - '
                return 100
            end
        rescue => exception
            @moesif_helpers.log_debug 'Error while geting sampling percentage, assuming default behavior'
            @moesif_helpers.log_debug exception.to_s
            return 100
        end
    end

    def decompress_gzip_body(config_api_response)
        # Decompress gzip response body
        begin
            # Check if the content-encoding header exist and is of type zip
            if config_api_response.headers.key?(:content_encoding) && config_api_response.headers[:content_encoding].eql?( 'gzip' ) then
                
                # Create a GZipReader object to read data
                gzip_reader = Zlib::GzipReader.new(StringIO.new(config_api_response.raw_body.to_s))
                
                # Read the body
                uncompressed_string = gzip_reader.read
                
                # Return the parsed body
                return JSON.parse( uncompressed_string )
            else
                @moesif_helpers.log_debug 'Content Encoding is of type other than gzip, returning nil'
                return nil
            end
        rescue => exception
            @moesif_helpers.log_debug 'Error while decompressing the response body'
            @moesif_helpers.log_debug exception.to_s
            return nil
        end
    end

    def calculate_weight(sample_rate)
        return sample_rate == 0 ? 1 : (100 / sample_rate).floor
    end
end
