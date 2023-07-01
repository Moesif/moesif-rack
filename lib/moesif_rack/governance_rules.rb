require 'moesif_api'
require 'json'
require 'time'
require 'stringio'
require_relative './moesif_helpers'
require_relative './regex_config_helper'

# rule refereence
# {
#   "_id": "649b64ea96d5e2384e3cece6",
#   "created_at": "2023-06-27T22:38:34.405",
#   "type": "regex",
#   "state": 2,
#   "org_id": "688:25",
#   "app_id": "768:74",
#   "name": "teset govern rule. ",
#   "block": true,
#   "applied_to": "matching",
#   "applied_to_unidentified": false,
#   "response": {
#       "status": 205,
#       "headers": {
#           "X-Test": "12423"
#       },
#       "body": {
#           "hello": "there"
#       }
#   },
#   "regex_config": [
#       {
#           "conditions": [
#               {
#                   "path": "request.route",
#                   "value": "test"
#               },
#               {
#                   "path": "request.verb",
#                   "value": "test"
#               }
#           ]
#       },
#       {
#           "conditions": [
#               {
#                   "path": "request.ip_address",
#                   "value": "teset"
#               },
#               {
#                   "path": "request.verb",
#                   "value": "5"
#               }
#           ]
#       }
#   ]
# }

# user rule reference.

# {
#   "_id": "649b65d83a5a0131fd035427",
#   "created_at": "2023-06-27T22:42:32.301",
#   "type": "user",
#   "state": 2,
#   "org_id": "688:25",
#   "app_id": "768:74",
#   "name": "test user rule",
#   "block": false,
#   "applied_to": "matching",
#   "applied_to_unidentified": true,
#   "response": {
#       "status": 200,
#       "headers": {
#           "teset": "test"
#       }
#   },
#   "cohorts": [
#       {
#           "id": "645c3793cba73323bb0760e6"
#       }
#   ],
#   "regex_config": [
#       {
#           "conditions": [
#               {
#                   "path": "request.verb",
#                   "value": "get"
#               }
#           ]
#       }
#   ]
# }

module APPLY_TO
  MATCHING = :matching
  NOT_MATCHING = :not_matching
end

module RULE_TYPES
  USER = :user
  COMPANY = :company
  REGEX = :regex
end

FIELDS_SUBJECT_TO_REGEX = {
  verb: {
    field: 'request.verb'
  },
  route: {
    field: 'request.route'
  }
}

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
    rules = decompress_gzip_body(rules_response)
    @last_fetch = Time.now.utc
    generate_rule_cache(rules)
  rescue MoesifApi::APIException => e
    if e.response_code.between?(401, 403)
      @moesif_helpers.log_debug 'Unauthorized access getting application configuration. Please check your Appplication Id.'
    end
    @moesif_helpers.log_debug 'Error getting application configuration, with status code:'
    @moesif_helpers.log_debug e.response_code
  rescue StandardError => e
    @moesif_helpers.log_debug e.to_s
  end

  def generate_rules_caching(rules)
    @rules = rules
    @regex_rules = []
    @user_rules = {}
    @unidentified_user_rules = []
    @company_rules = {}
    @unidentified_company_rules = []
    if !rules.nil? && !rules.empty?
      rules.each do |rule|
        rule_id = rule.fetch('_id')
        applied_to_unidentified
        case rule.fetch(:type)
        when RULE_TYPES::USER
          @user_rules[rule_id] = rule
          @unidentified_user_rules.push(rule) if rule.fetch(:applied_to_unidentified, false)
        when RULE_TYPES::COMMPNAY
          @company_rules[rule_id] = rule
          @unidentified_company_rules.push(rule) if rule.fetch(:applied_to_unidentified, false)
        when RULE_TYPES::REGEX
          @regex_rules.push(rule)
        else
          @moesif_helpers.log_debug 'rule type not found for id ' + rule_id
        end
      end
    end
  rescue StandardError => e
    @moesif_helpers.log_debug e.to_s
  end

  def reload_rules_if_needed(api_controller)
    # ten minutes to refech
    return unless Time.now.utc > (60 * 10 + @last_fetch)

    get_rules(api_controller)
  end

  # TODO
  def convert_uri_to_route(uri)
    # TODO: for now just retur uri
    uri
  end

  def prepare_request_fields_based_on_regex_config(_env, _event_model)
    field_values = {
      'request.verb': _event_model.dig('request', 'verb'),
      'request.ip_address': _event_model.dig('request', 'ip_address'),
      'request.route': convert_uri_to_route(_event_model.dig('request', 'uri')),
      'request.body.operationName': _event_model.dig('request', 'body', 'operationName')
    }

    # TODO: for body
    request_body = _event_model.dig('request', 'body')

    field_values['request.body'] = request_body if request_body

    field_values
  end

  def get_field_value_for_path(path, request_fields, _request_body)
    if path.starts_with?('request.body.') && _request_body
      body_key = path.sub('request.body.', '')
      return _request_body.fetch(body_key)
    end
    request_fields.fetch(path)
  end

  def check_request_with_regex_math(regex_configs, request_fields, _request_body)
    array_to_or = regex_configs.map do |or_group_of_regex_rule|
      conditions = or_group_of_regex_rule.fetch('conditions', [])

      conditions.reduce(true) do |all_match, condition|
        return false unless all_match

        path = condition.fetch('path')

        field_value = get_field_value_for_path(path, request_fields, _request_body)
        reg_ex = Regexp.new condition.fetch('value')

        field_value =~ reg_ex
      end
    end

    array_to_or.reduce(false) { |anysofar, curr| anysofar || curr }
  end

  def get_rules_if_governance_rule_matched(_env, _event_model)
    request_fields = prepare_request_fields_based_on_regex_config(_env, _event_model)
    # FIXME
    request_body = _event_model.dig('request', 'body')

    @regex_rules.select do |rule|
      regex_configs = rule.fetch('regex_config')
      return false unless regex_config

      matched = check_request_with_regex_match(regex_configs, request_fields, request_body)
      matched
    end
  end

  def apply_regex_rules(_config, _env, _event_model, _status, _headers, _body)
    return if @regex_rules.empty?

    matched_rules = get_rules_if_governance_rule_matched(_env, _event_model)
    return if matched_rules.empty? || matched_rules.nil?

    matched_rules.reduce do |prev_response, _rule|
      prev_status = prev_response.nil? ? _status : prev_response[:status]
      prev_headers = prev_response.nil? ? _headers : prev_response[:headers]
      prev_body = prev_respond.nil ? _body : prev_response[:body]
      modiify_response_for_matched_rule(_rule, _status, _headers, _body)
    end
  end

  def replace_merge_tag_values(template_obj, mergetag_values)
    # take the template, either headers or body, and replace with mergetag_values
    # recursively
    return template_obj unless mergedtag_values

    result_hash = {}
    template_obj.each do |key, template_value|
      
    end
  end

  def modify_reponse_for_matched_rule(rule, _status, _headers, _body, _mergetag_values)
    # For matched rule, we can now modify the response
    # response is a hash with :status, :headers and :body or nil
    return unless rule[:blocking]
  end

  def govern_request(_config, _env, _user_id, _company_id, _event_model)
    # we can skip if rules does not exist or config does not exist
    return [] if @rules.nil? || _config.nil?

    # apply in reverse order of priority.
    # Priority is user rule, company rule, and regex.
    # by apply in reverse order, the last rule is highest priority.

    company_id_matched_rule_ids = _config.dig('company_rules', _company_id)
    unless company_id_matched_ruled_ids.nil?
      # apply compnay rule.
    end

    user_id_matched_rule_ids = _config.dig('user_rules', _user_id)
    unless user_id_matched_rule_ids.nil?
      # apply user rule
    end

    [block, new_status, additional_headers, new_body]
  end
end
