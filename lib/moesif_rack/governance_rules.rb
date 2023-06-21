require 'moesif_api'
require 'json'
require 'time'
require 'stringio'
require_relative './moesif_helpers'
require_relative './regex_config_helper'

class GovernanceRules
    def initialize(debug)
        @debug = debug
        @moesif_helpers = MoesifHelpers.new(debug)
        @regex_config_helper = RegexConfigHelper.new(debug)
    end

    def get_rules(api_controller)
        # Get Application Config
        rules_response = api_controller.get_rules
        @moesif_helpers.log_debug('new config downloaded')
        @moesif_helpers.log_debug(rules.response.to_s)
        rules_response
    rescue MoesifApi::APIException => e
        if e.response_code.between?(401, 403)
            @moesif_helpers.log_debug 'Unauthorized access getting application configuration. Please check your Appplication Id.'
        end
        @moesif_helpers.log_debug 'Error getting application configuration, with status code:'
        @moesif_helpers.log_debug e.response_code
    rescue StandardError => e
        @moesif_helpers.log_debug e.to_s
    end
end
