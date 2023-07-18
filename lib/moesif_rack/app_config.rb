require 'moesif_api'
require 'json'
require 'time'
require 'zlib'
require 'stringio'
require_relative './moesif_helpers'
require_relative './regex_config_helper'

class AppConfig
  attr_accessor :config, :recent_etag, :last_download_time

  def initialize(debug)
    @debug = debug
    @moesif_helpers = MoesifHelpers.new(debug)
    @regex_config_helper = RegexConfigHelper.new(debug)
  end

  def should_reload(etag_from_create_event)
    if @last_download_time.nil?
      return true
    elsif Time.now.utc > (@last_config_download_time + 300)
      return true
    elsif !etag_from_create_event.nil? && !@recent_etag.nil?
      @moesif_helpers.log_debug('comparing if etag from event and recent etag match ' + etag_from_create_event + ' ' + @recent_etag)

      return etag_from_create_event != @recent_etag
    end
    @moesif_helpers.log_debug('should skip reload config')
    return false;
  end

  def get_config(api_controller)
    # Get Application Config
    @moesif_helpers.log_debug('try to loading etag')
    config_json, _context = api_controller.get_app_config
    @config = config_json
    @recent_etag = _context.response.headers[:x_moesif_config_etag]
    @last_download_time = Time.now.utc
    @moesif_helpers.log_debug('new config downloaded')
    @moesif_helpers.log_debug(config_json.to_s)
  rescue MoesifApi::APIException => e
    if e.response_code.between?(401, 403)
      @moesif_helpers.log_debug 'Unauthorized access getting application configuration. Please check your Appplication Id.'
    end
    @moesif_helpers.log_debug 'Error getting application configuration, with status code:'
    @moesif_helpers.log_debug e.response_code
  rescue StandardError => e
    @moesif_helpers.log_debug e.to_s
  end

  def get_sampling_percentage(event_model, user_id, company_id)
    # Get sampling percentage
      @moesif_helpers.log_debug("Getting sample rate for user #{user_id} company #{company_id}")
      @moesif_helpers.log_debug(@config.to_s)

      # if we do not have config for some reason we return 100
      return 100 if @config.nil?

      # Get Regex Sampling rate
      regex_config = @config.fetch('regex_config', nil)

      if !regex_config.nil? and !event_model.nil?
        config_mapping = @regex_config_helper.prepare_config_mapping(event_model)
        regex_sample_rate = @regex_config_helper.fetch_sample_rate_on_regex_match(regex_config,
                                                                                  config_mapping)
        return regex_sample_rate unless regex_sample_rate.nil?
      end

      # Get user sample rate object
      user_sample_rate = @config.fetch('user_sample_rate', nil)

      # Get company sample rate object
      company_sample_rate = @config.fetch('company_sample_rate', nil)

      # Get sample rate for the user if exist
      if !user_id.nil? && !user_sample_rate.nil? && user_sample_rate.key?(user_id)
        return user_sample_rate.fetch(user_id)
      end

      # Get sample rate for the company if exist
      if !company_id.nil? && !company_sample_rate.nil? && company_sample_rate.key?(company_id)
        return company_sample_rate.fetch(company_id)
      end

      # Return overall sample rate
      @config.fetch('sample_rate', 100)
    else
      @moesif_helpers.log_debug 'Assuming default behavior as response body is nil - '
      100
    end
  rescue StandardError => e
    @moesif_helpers.log_debug 'Error while geting sampling percentage, assuming default behavior'
    @moesif_helpers.log_debug e.to_s
    100
  end

  def calculate_weight(sample_rate)
    sample_rate == 0 ? 1 : (100 / sample_rate).floor
  end
end
