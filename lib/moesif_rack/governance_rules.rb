require 'moesif_api'
require 'json'
require 'time'
require 'zlib'
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

module RULE_TYPES
  USER = "user"
  COMPANY = "company"
  REGEX = "regex"
end

class GovernanceRules
  def initialize(debug)
    @debug = debug
    @moesif_helpers = MoesifHelpers.new(debug)
    @regex_config_helper = RegexConfigHelper.new(debug)
    @last_fetch = Time.at(0)
  end

  def load_rules(api_controller)
    # Get Application Config
    @moesif_helpers.log_debug('starting downlaoding rules')
    rules_response = api_controller.get_rules
    rules = @moesif_helpers.decompress_gzip_body(rules_response)
    @last_fetch = Time.now.utc
    @moesif_helpers.log_debug('new rules downloaded')
    @moesif_helpers.log_debug(rules.to_json)

    generate_rules_caching(rules)
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
        rule_id = rule['_id']
        case rule["type"]
        when RULE_TYPES::USER
          @user_rules[rule_id] = rule
          @unidentified_user_rules.push(rule) if rule.fetch("applied_to_unidentified", false)
        when RULE_TYPES::COMPANY
          @company_rules[rule_id] = rule
          @unidentified_company_rules.push(rule) if rule.fetch("applied_to_unidentified", false)
        when RULE_TYPES::REGEX
          @regex_rules.push(rule)
        else
          @moesif_helpers.log_debug 'rule type not found for id ' + rule_id
        end
      end
    end
    # @moesif_helpers.log_debug('user_rules processed ' + @user_rules.to_s)
    # @moesif_helpers.log_debug('unidentified_user_rules' + @unidentified_user_rules.to_s);
    # @moesif_helpers.log_debug('regex_rules' + @regex_rules.to_s);
  rescue StandardError => e
    @moesif_helpers.log_debug e.to_s
  end

  def reload_rules_if_needed(api_controller)
    # ten minutes to refech
    print Time.now.utc
    return unless Time.now.utc > (@last_fetch + 60 * 10)

    load_rules(api_controller)
  end

  def has_rules
    return false if @rules.nil?
    @rules.length >= 1
  end

  # TODO
  def convert_uri_to_route(uri)
    # TODO: for now just return uri
    uri
  end

  def prepare_request_fields_based_on_regex_config(_env, event_model)
    {
      'request.verb' => event_model.dig('request', 'verb'),
      'request.ip_address' => event_model.dig('request', 'ip_address'),
      'request.route' => convert_uri_to_route(event_model.dig('request', 'uri')),
      'request.body.operationName' => event_model.dig('request', 'body', 'operationName')
    }
  end

  def get_field_value_for_path(path, request_fields, request_body)
    if path && path.start_with?('request.body.') && request_body
      body_key = path.sub('request.body.', '')
      return request_body.fetch(body_key, nil)
    end
    request_fields.fetch(path, nil)
  end

  def check_request_with_regex_match(regex_configs, request_fields, request_body)
    array_to_or = regex_configs.map do |or_group_of_regex_rule|
      conditions = or_group_of_regex_rule.fetch('conditions', [])

      conditions.reduce(true) do |all_match, condition|
        return false unless all_match

        path = condition.fetch('path', nil)

        field_value = get_field_value_for_path(path, request_fields, request_body)
        reg_ex = Regexp.new condition.fetch('value', nil)

        if path.nil? || field_value.nil? || reg_ex.nil?
          false
        else
          field_value =~ reg_ex
        end
      end
    end

    array_to_or.reduce(false) { |anysofar, curr| anysofar || curr }
  end

  def get_applicable_regex_rules(request_fields, request_body)
    @regex_rules.select do |rule|
      regex_configs = rule['regex_config']
      @moesif_helpers.log_debug("checking regex_configs")
      @moesif_helpers.log_debug(regex_configs.to_s)
      if regex_configs.nil?
        true
      else
        @moesif_helpers.log_debug("checking regex_configs")
        @moesif_helpers.log_debug(regex_configs.to_s)
        check_request_with_regex_match(regex_configs, request_fields, request_body)
      end
    end
  end

  def get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
    @unidentified_user_rules.select do |rule|
      @moesif_helpers.log_debug('check unidnetified user rule ' + rule.to_s)
      regex_matched = check_request_with_regex_match(rule.fetch('regex_config'), request_fields, request_body)
      @moesif_helpers.log_debug('regexmatched')
      @moesif_helpers.log_debug(regex_matched)

      regex_matched
    end
  end

  def get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    applicable_rules_list = []

    rule_ids_hash_that_is_in_cohort = {}

    # handle uses where user_id is in ARLEADY in the cohort of the rules.
    # if user is in a cohorot of the rule, it will come from config user rule values array, which is
    # config.user_rules.user_id.[]
    if !config_user_rules_values.nil?
      config_user_rules_values.each do |entry|
        rule_id = entry["rules"]
        # this is user_id matched cohort set in the rule.
        mergetag_values = entry["values"]
        rule_ids_hash_that_is_in_cohort[rule_id] = true unless rule_id.nil?
        # rule_ids_hash_that_I_am_in_cohot{629847be77e75b13635aa868: true}

        found_rule = @user_rules[rule_id]
        if found_rule.nil?
          @moesif_helpers.log_debug('rule for not foun for ' + rule_id.to_s)
          next
        end

        @moesif_helpers.log_debug('found rule in cached user rules' + rule_id)

        regex_matched = check_request_with_regex_match(found_rule.fetch('regex_config'), request_fields, request_body)

        if !regex_matched
          @moesif_helpers.log_debug('regex not matched, skipping ' + rule_id.to_s)
          next
        end

        if found_rule["applied_to"] == 'not_matching'
          # mean not matching, i.e. we do not apply the rule since current user is in cohort.
          @moesif_helpers.log_debug('applied to is not matching' + "so skipping add this rule")
          next
        else
          # since applied_to is matching, we are in the cohort, we apply the rule by adding it to the list.
          @moesif_helpers.log_debug('applied to is matching' + found_rule["applied_to"])
          applicable_rules_list.push(found_rule)
        end
      end
    end

    # now user id is NOT associated with any cohort rule so we have to add user rules that is "Not matching"
    @user_rules.each do |_rule_id, rule|
      # we want to apply to any "not_matching" rules.
      # we want to make sure user is not in the cohort of the rule.
      if rule["applied_to"] == 'not_matching' && !rule_ids_hash_that_is_in_cohort[_rule_id]
        regex_matched = check_request_with_regex_match(rule.fetch('regex_config', nil), request_fields, request_body)
        if regex_matched
          applicable_rules_list.push(rule)
        end
      end
    end

    applicable_rules_list
  end

  def get_applicable_company_rules_for_unidentified_company(request_fields, request_body)
    @unidentified_company_rules.select do |rule|
      regex_matched = check_request_with_regex_match(rule.fetch('regex_config'), request_fields, request_body)

      regex_matched
    end
  end

  def get_applicable_company_rules(request_fields, request_body, config_company_rules_values)
    applicable_rules_list = []

    rule_ids_hash_that_is_in_cohort = {}

    # handle where company_id is in the cohort of the rules.
    if !config_company_rules_values.nil?
      config_company_rules_values.each do |entry|
        rule_id = entry["rules"]
        # this is user_id matched cohort set in the rule.
        mergetag_values = entry["values"]

        rule_ids_hash_that_is_in_cohort[rule_id] = true unless rule_id.nil?

        found_rule = @company_rules[rule_id]

        if found_rule.nil?
          @moesif_helpers.log_debug('company rule for not found for ' + rule_id.to_s)
          next
        end

        regex_matched = check_request_with_regex_match(found_rule.fetch('regex_config'), request_fields, request_body)

        if !regex_matched
          @moesif_helpers.log_debug('regex not matched, skipping ' + rule_id.to_s)
          next
        end

        if found_rule["applied_to"] != 'not_matching'
          # means matching, i.e. we apply the rule since user is in cohort.
          applicable_rules_list.push(found_rule)
        end
      end
    end

    # handle is NOT in the cohort of rule so we have to apply rules that are "Not matching"
    @company_rules.each do |_rule_id, rule|
      # we want to apply to any "not_matching" rules.
      if rule["applied_to"] == 'not_matching' && !rule_ids_hash_that_is_in_cohort[_rule_id]
        regex_matched = check_request_with_regex_match(rule.fetch('regex_config', nil), request_fields, request_body)
        if regex_matched
          applicable_rules_list.push(rule)
        end
      end
    end
    applicable_rules_list
  end

  def replace_merge_tag_values(template_obj_or_val, mergetag_values, variables_from_rules)
    # take the template, either headers or body, and replace with mergetag_values
    # recursively
    # return template_obj_or_val unless !mergetag_values.nil?

    if template_obj_or_val.nil?
      return template_obj_or_val
    elsif template_obj_or_val.is_a?(String)
      temp_val = template_obj_or_val
      mergetag_values.each { |merge_key, merge_value| temp_val = temp_val.sub('{{' + merge_key + '}}', merge_value) }
      return temp_val
    elsif template_obj_or_val.is_a?(Array)
      return tempplate_obj_or_val.map { |entry| replace_merge_tag_values(entry, mergetag_values) }
    elsif template_obj_or_val.is_a?(Hash)
      result_hash = {}
      template_obj_or_val.each do |key, entry|
        result_hash[key] = replace_merge_tag_values(entry, mergetag_values)
      end
      return result_hash
    else
      return template_obj_or_val
    end
  end

  def modify_response_for_applicable_rule(rule, response, mergetag_values)
    # For matched rule, we can now modify the response
    # response is a hash with :status, :headers and :body or nil
    @moesif_helpers.log_debug('about to modify response ' + mergetag_values.to_s)
    new_headers = response[:headers].clone
    rule_variabes = rule["variables"]
    # headers are always merged togethe
    rule_headers = replace_merge_tag_values(rule.dig('response', 'headers'), mergetag_values, rule_variabes)
    # it is an insersion of rule headers not replacement.
    rule_headers.each { |key, entry| new_headers[key] = entry } unless rule_headers.nil?

    response[:headers] = new_headers

    # only replace status and body if it is blocking.
    if rule["block"]
      @moesif_helpers.log_debug('rule is block' + rule[:response].to_s)
      response[:status] = rule.dig('response', 'status') || response[:status]
      new_body = replace_merge_tag_values(rule.dig('response', 'body'), mergetag_values, rule_variables)
      response[:body] = new_body
      response[:block_rule_id] = rule["_id"]
    end

    response
  end

  def apply_rules_list(applicable_rules, response, config_rule_values)
    if applicable_rules.nil? || applicable_rules.empty?
      return response
    end

    applicable_rules.reduce(response) do |prev_response, rule|
      if config_rule_values
        found_rule_value_pair = config_rule_values.find { |rule_value_pair| rule_value_pair["rules"] == rule["_id"] }
        mergetag_values = found_rule_value_pair["values"] unless found_rule_value_pair.nil?
      end
      modify_response_for_applicable_rule(rule, prev_response, mergetag_values)
    end
  end

  def govern_request(config, env, event_model, status, headers, body)
    # we can skip if rules does not exist or config does not exist
    return if @rules.nil? || @rules.empty?

    request_fields = prepare_request_fields_based_on_regex_config(env, event_model)
    request_body = event_model.dig('request', 'body')
    user_id = event_model.fetch('user_id', nil)
    company_id = event_model.fetch('company_id', nil)

    # apply in reverse order of priority.
    # Priority is user rule, company rule, and regex.
    # by apply in reverse order, the last rule become highest priority.

    new_response = {
      status: status,
      headers: headers,
      body: body
    }

    applicable_regex_rules = get_applicable_regex_rules(request_fields, request_body)
    new_response = apply_rules_list(applicable_regex_rules, new_response, nil)

    if company_id.nil?
      company_rules = get_applicable_company_rules_for_unidentified_company(request_fields, request_body)
      new_response = apply_rules_list(company_rules, new_response, nil)
    else
      config_rule_values = config.dig('company_rules', company_id) unless config.nil?
      company_rules = get_applicable_user_rules(request_fields, request_body, config_rule_values)
      new_response = apply_rules_list(company_rules, new_response, config_rule_values)
    end

    if user_id.nil?
      user_rules = get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
      new_response = apply_rules_list(user_rules, new_response, nil)
    else
      config_rule_values = config.dig('user_rules', user_id) unless config.nil?
      user_rules = get_applicable_user_rules(request_fields, request_body, config_rule_values)
      new_response = apply_rules_list(user_rules, new_response, config_rule_values)
    end
    new_response
  rescue StandardError => e
    @moesif_helpers.log_debug "error try to govern request:" + e.to_s + "for event" + event_model.to_s
  end

end
