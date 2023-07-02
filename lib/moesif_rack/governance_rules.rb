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
    # TODO: for now just return uri
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

  def check_request_with_regex_match(regex_configs, request_fields, _request_body)
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

  def get_applicable_regex_rules(request_fields, request_body)
    @regex_rules.select do |rule|
      regex_configs = rule.fetch('regex_config')
      return false unless regex_config

      matched = check_request_with_regex_match(regex_configs, request_fields, request_body)
      matched
    end
  end

  def get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
    applicable_unidentified_rules = @unidentified_user_rules.select do |rule|
      # matching is an allow rule
      # we only care about deny rules.
      regex_matched = check_request_with_regex_match(rule.fetch('regex_config'), rqeuest_fields, request_body)

      # default is "matching" so if nil means "matching"
      if rule[:applied_to] == 'not_matching'
        return !regex_matched
      else
        return regex_matched
    end

    applicable_unidentified_rules
  end

  def get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    applicable_rules_list = []

    # handle uses where user_id is in the cohort of the rules.
    if config_user_rules_values
      config_user_rules_values.each do | entry |
        rule_id = entry[:rules]
        # this is user_id matched cohort set in the rule.
        mergetag_values = entry[:values]

        found_rule = @user_rules[rule_id]
        if !found_rule.nil?
          regex_matched = check_request_with_regex_match(found_rule.fetch('regex_config'), rqeuest_fields, request_body)

          if found_rule[:applied_to] == "not_matching" && !regex_matched
            # if regex did not match, the user_id matched above, it is considered not matched, we still apply the rule..
            applicable_rules_list.push(found_rule)
          elsif regex_matched
            applicable_rules_list.push(found_rule)
        end
      end
    end
    # now user id is NOT associated with any cohort
    @user_rules.each do |rule_id, rule|
      # we want to apply to any "not_matching" rules.
      # here regex does not matter since it is already NOT matched.
      if rule[:applied_to] == "not_matching"
        applicable_rules_list.push(rule)
      end
    end

    applicable_rules_list
  end


  def get_applicable_company_rules_for_unidentified_company(request_fields, request_body)
    applicable_unidentified_rules = @unidentified_company_rules.select do |rule|
      # matching is an allow rule
      # we only care about deny rules.
      regex_matched = check_request_with_regex_match(rule.fetch('regex_config'), request_fields, request_body)

      # default is "matching" so if nil means "matching"
      if rule[:applied_to] == 'not_matching'
        return !regex_matched
      else
        return regex_matched
    end

    applicable_unidentified_rules
  end


  def get_applicable_company_rules(request_fields, request_body, config_company_rules_values)
    applicable_rules_list = []

    # handle uses where user_id is in the cohort of the rules.
    if config_company_rules_values
      config_company_rules_values.each do | entry |
        rule_id = entry[:rules]
        # this is user_id matched cohort set in the rule.
        mergetag_values = entry[:values]

        found_rule = @company_rules[rule_id]
        if !found_rule.nil?
          regex_matched = check_request_with_regex_match(found_rule.fetch('regex_config'), rqeuest_fields, request_body)

          if found_rule[:applied_to] == "not_matching" && !regex_matched
            # if regex did not match, the user_id matched above, it is considered not matched, we still apply the rule..
            applicable_rules_list.push(found_rule)
          elsif regex_matched
            applicable_rules_list.push(found_rule)
        end
      end
    end
    # now user id is NOT associated with any cohort
    @company_rules.each do |rule_id, rule|
      # we want to apply to any "not_matching" rules.
      # here regex does not matter since it is already NOT matched.
      if rule[:applied_to] == "not_matching"
        applicable_rules_list.push(rule)
      end
    end

    applicable_rules_list
  end

  def replace_merge_tag_values(template_obj_or_val, mergetag_values)
    # take the template, either headers or body, and replace with mergetag_values
    # recursively
    return template_obj_or_val unless mergedtag_values

    if template_obj_or_val.nil?
      template_obj_or_val
    elsif template_value.is_a?(String)
      temp_val = template_value
      mergetag_values.each { |merge_key, merge_value| temp_val = temp_val.sub(merge_key, merge_value) }
      temp_val
    elsif template_obj_or_val.is_a?(Array)
      tempplate_obj_or_val.map { |entry| replace_merge_tag_values(entry, mergetag_values) }
    elsif template_obj_or_val.is_a?(Hash)
      result_hash = {}
      template_obj_or_val.each do |key, entry|
        result_hash[key] = replace_merge_tag_values(entry, mergetag_values)
      end
    else
      template_obj_or_val
    end
  end

  def modify_response_for_applicable_rule(rule, status, headers, body, mergetag_values)
    # For matched rule, we can now modify the response
    # response is a hash with :status, :headers and :body or nil
    new_headers = headers.clone
    # add headers
    rule_headers = replace_merge_tag_values(rule.dig('response', 'headers'), mergetag_values)
    # it is an insersion of rule headers not replacement.
    rule_headers.each { |key, entry| new_headers[key] = entry } if rule_headers

    new_status = status
    new_body = body

    if rule[:blocking]
      new_status = rule.dig('response', 'status') || status
      new_body = replace_merge_tag_values(rule.dig('response', 'body'), mergetag_values)
    end

    { :status => new_status, :headers => new_headers, :body => new_body }
  end

  def apply_rules_list(matched_rules, curr_status, curr_headers, curr_body, config_rule_values)
    if matched_rules.nil? || matched_rules.empty?
      return {:status => curr_status, :headers => curr_headers, :body => curr_body}
    end

    matched_rules.reduce do |prev_response, rule|
      if config_rule_values
        found_rule_value_pair = config_rule_values.find { |rule_value_pair| rule_value_pair[:rules] = rule[:_id] }
        mergetag_values = found_rule_value_pair[:values] if found_rule_value_pair
      end
      prev_status = prev_response.nil? ? curr_status : prev_response[:status]
      prev_headers = prev_response.nil? ? curr_headers : prev_response[:headers]
      prev_body = prev_response.nil ? curr_body : prev_response[:body]
      modify_response_for_applicable_rule(rule, prev_status, prev_headers, prev_body, mergetag_values)
    end
  end

  def govern_request(config, env, event_model, user_id, company_id, status, headers, body)
    # we can skip if rules does not exist or config does not exist
    return if @rules.nil? || @rules.empty?

    request_fields = prepare_request_fields_based_on_regex_config(env, event_model)
    request_body = event_model.dig('request', 'body')

    # apply in reverse order of priority.
    # Priority is user rule, company rule, and regex.
    # by apply in reverse order, the last rule become highest priority.

    new_response = {
      :status => status,
      :headers => headers,
      :body => body
    }

    applicable_regex_rules = get_applicable_regex_rules(request_fields, request_body)
    new_response = apply_rules_list(applicable_regex_rules, new_response[:status], new_response[:headers], new_response[:body])

    if company_id.nil?
      company_rules = get_applicable_company_rules_for_unidentified_company(request_fields, request_body)
      new_response = apply_rules_list(company_rules, new_response[:status], new_response[:headers], new_response[:body])
    elsif
      config_rule_values = config.dig('company_rules', company_id) if !config.nil?
      company_rules = get_applicable_user_rules(request_fields, request_body, config_rule_values)
      new_response = apply_rules_list(company_rules, new_response[:status], new_response[:headers], new_response[:body], config_rule_values)
    end

    if user_id.nil?
      user_rules = get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
      new_response = apply_rules_list(user_rules, new_response[:status], new_response[:headers], new_response[:body])
    elsif
      config_rule_values = config.dig('user_rules', user_id) if !config.nil?
      user_rules = get_applicable_user_rules(request_fields, request_body, config_rule_values)
      new_response = apply_rules_list(user_rules, new_response[:status], new_response[:headers], new_response[:body], config_rule_values)
    end

    new_response
  end
end
