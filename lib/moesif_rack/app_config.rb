require 'moesif_api'
require 'json'
require 'time'
require 'zlib'
require 'stringio'

class AppConfig

    def get_config(api_controller, debug)
        # Get Application Config
        begin 
            config_api_response = api_controller.get_app_config()
            return config_api_response
        rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
                puts 'Unauthorized access getting application configuration. Please check your Appplication Id.'
            end
            if debug
                puts 'Error getting application configuration, with status code:'
                puts e.response_code
            end
        end
    end

    def parse_configuration(config_api_response, debug)
        # Parse configuration object and return Etag, sample rate and last updated time
        begin
            # Rails return gzipped compressed response body, so decompressing it and getting JSON response body
            response_body = decompress_gzip_body(config_api_response, debug)

            # Check if response body is not nil
            if !response_body.nil? then 
                # Return Etag, sample rate and last updated time
                return config_api_response.headers[:x_moesif_config_etag], response_body.fetch("sample_rate", 100), Time.now.utc
            else
                if debug
                    puts 'Response body is nil, assuming default behavior'
                end
                # Response body is nil, so assuming default behavior
                return nil, 100, Time.now.utc
            end
        rescue => exception
            if debug
                puts 'Error while parsing the configuration object, assuming default behavior'
                puts exception.to_s
            end
            # Assuming default behavior
            return nil, 100, Time.now.utc
        end
    end

    def get_sampling_percentage(config_api_response, user_id, company_id, debug)
        # Get sampling percentage
        begin
            # Rails return gzipped compressed response body, so decompressing it and getting JSON response body
            response_body = decompress_gzip_body(config_api_response, debug)

            # Check if response body is not nil
            if !response_body.nil? then 
                
                # Get user sample rate object
                user_sample_rate = response_body.fetch('user_sample_rate', nil)

                # Get company sample rate object
                company_sample_rate = response_body.fetch('company_sample_rate', nil)

                # Get sample rate for the user if exist
                if !user_id.nil? && !user_sample_rate.nil? && user_sample_rate.key?(user_id)
                    return user_sample_rate.fetch(user_id)
                end

                # Get sample rate for the company if exist
                if !company_id.nil? && !company_sample_rate.nil? && company_sample_rate.key?(company_id)
                    return company_sample_rate.fetch(company_id)
                end

                # Return sample rate
                return response_body.fetch('sample_rate', 100)
            else 
                if debug
                    puts 'Assuming default behavior as response body is nil - '
                end
                return 100
            end
        rescue => exception
            if debug
                puts 'Error while geting sampling percentage, assuming default behavior'
            end
            return 100
        end
    end

    def decompress_gzip_body(config_api_response, debug)
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
                if debug
                    puts 'Content Encoding is of type other than gzip, returning nil'
                end
                return nil
            end
        rescue => exception
            if debug
                puts 'Error while decompressing the response body'
                puts exception.to_s
            end
            return nil
        end
    end

    def calculate_weight(sample_rate)
        return sample_rate == 0 ? 1 : (100 / sample_rate).floor
    end
end
