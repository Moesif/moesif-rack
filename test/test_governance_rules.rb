require 'moesif_api'
require 'test/unit'
require 'rack'
require 'net/http'
require_relative '../lib/moesif_rack/app_config'
require_relative '../lib/moesif_rack'
require_relative '../lib/moesif_rack/governance_rules'

class GovernanceRulesTest < Test::Unit::TestCase
  self.test_order = :defined
  def setup
    return if @already_setup
    @goverance_rule_manager = GovernanceRules.new(true)
    @api_client = MoesifApi::MoesifAPIClient.new('Your Moesif Application Id')
    @goverance_rule_manager.reload_rules_if_needed(@api_client.api)
    @already_setup = true
  end

  # def test_load
  #   @goverance_rule_manager.reload_rules_if_needed(@api_client.api)
  # end

  def test_get_applicable_regex_rules
    request_fields = {
      'request.verb' => 'GET',
      'request.ip_address' => '125.2.3.2',
      'request.route' => "",
      'request.body.operationName' => "operator name"
    }
    request_body = {
      "subject" => "should_block"
    }

    applicable_rules = @goverance_rule_manager.get_applicable_regex_rules(request_fields, request_body)
    print "\nFound #{applicable_rules.length} applicable rule for regex only rules-------\n"
    print applicable_rules.to_s
    print "\n-------------\n"
    assert(applicable_rules.length === 1, "expect to get at least one regex rule")
  end


  def test_get_applicable_user_rules_for_unidentified_user
    request_fields = {
      'request.route' => "test/no_italy",
    }
    request_body = {
      "subject" => "should_block"
    }
    applicable_rules = @goverance_rule_manager.get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
    print "\nFound #{applicable_rules.length} applicable rule for anonymous user-------\n"
    print applicable_rules.to_s
    print "\n-------------\n"
    assert(applicable_rules.length === 1, "expect to get 1 unidentified user rules")
  end

  def test_get_applicable_user_rules_for_matching
    request_fields = {
      'request.route' => "test/no_italy",
    }
    request_body = {
      "subject" => "should_block"
    }
    user_id = 'rome1'

    #for user id matched rules it depends on getting from config_rules_values
    #for that particular user id.
    # for this test case I will use this rule as fake input
    #https://www.moesif.com/wrap/app/88:210-1051:5/governance-rule/64a5b8f9aca3042266d36ebc
    config_user_rules_values = [
      {
        "rules" => "64a5b8f9aca3042266d36ebc",
        "values" => {
          "0" => "rome",
          "1" => "some value for 1",
          "2" => "some value for 2",
        }
      }
    ]

    applicable_rules = @goverance_rule_manager.get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    print "\nFound #{applicable_rules.length} applicable rule for identified user based on event and config user rule values-------\n"
    print applicable_rules.to_s
    print "\n-------------\n"
    assert(applicable_rules.length === 1, "expect 1 rules")

    fake_response = {
      status: 200,
      headers: {
        "original-header" => "should be preserved"
      },
      body: {
        "foo_bar" => "if not blocked this would show"
      }
    }

    new_response = @goverance_rule_manager.apply_rules_list(applicable_rules, fake_response, config_user_rules_values);
    print "new resposne is: \n"
    print new_response.to_s
    print "\n------------------\n"
  end


  def test_get_applicable_user_rules_in_cohort_but_rule_is_apply_to_not_in_cohort
    request_fields = {
      'request.route' => "hello/canada",
    }
    request_body = {
      "from_location" => "canada"
    }
    user_id = 'vancouver1'

    config_user_rules_values = [
      {
        "rules" => "64a5b8fa3660b60f7c7662fc",
        "values" => {
          "0" => "city",
          "1" => "some value for 1",
          "2" => "some value for 2",
        }
      }
    ]

    applicable_rules = @goverance_rule_manager.get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    print "\nFound #{applicable_rules.length} applicable rule for identified user in cohort rule rule apply to not in cohort-------\n"
    print applicable_rules.to_s
    print "\n-------------\n"
    assert(applicable_rules.length === 0, "expect 0 rules, since user is in cohort, the rule is apply to users not in cohort")

    fake_response = {
      status: 200,
      headers: {
        "original-header" => "should be preserved"
      },
      body: {
        "foo_bar" => "if not blocked this would show"
      }
    }

    new_response = @goverance_rule_manager.apply_rules_list(applicable_rules, fake_response, config_user_rules_values);
    print "new response is: \n"
    print new_response.to_s
    print "\n------------------\n"
  end


  def test_get_applicable_user_not_in_any_cohort_but_regex_matched
    request_fields = {
      'request.route' => "hello/canada",
    }
    request_body = {
      "from_location" => "canada"
    }
    user_id = 'some_random_user'

    # since user didn't match any cohort, the config_user_rule_values is nil
    config_user_rules_values = nil;

    applicable_rules = @goverance_rule_manager.get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    print "\nFound #{applicable_rules.length} applicable rule for identified user no in any cohort, but rule apply to not in cohort-------\n"
    print applicable_rules.to_json
    print "\n-------------\n"
    assert(applicable_rules.length === 1, "expect 1 rules, since user is not in cohort, there is a apply to not in cohort rule with same regex maching")

    fake_response = {
      status: 200,
      headers: {
        "original-header" => "should be preserved"
      },
      body: {
        "foo_bar" => "if not blocked this would show"
      }
    }

    new_response = @goverance_rule_manager.apply_rules_list(applicable_rules, fake_response, config_user_rules_values);
    print "new resposne is: \n"
    print new_response.to_json
    print "\n------------------\n"
  end


  def test_apply_multiple_rules
    # this should match regex from one rule
    request_fields = {
      'request.route' => "hello/canada",
    }
    # this should match regex from another rule
    request_body = {
      "from_location" => "cairo"
    }

        # since user didn't match any cohort, the config_user_rule_values is nil
    config_user_rules_values = nil;

    applicable_rules = @goverance_rule_manager.get_applicable_user_rules(request_fields, request_body, config_user_rules_values)
    print "\nFound #{applicable_rules.length} applicable rule for in cohort rule rule apply to not in cohort-------\n"
    print applicable_rules.to_json
    print "\n-------------\n"
    assert(applicable_rules.length === 2, "expect 2 rules, since user is not in cohort, regex should match 2 rules")

    fake_response = {
      status: 200,
      headers: {
        "original-header" => "should be preserved"
      },
      body: {
        "foo_bar" => "if not blocked this would show"
      }
    }

    new_response = @goverance_rule_manager.apply_rules_list(applicable_rules, fake_response, config_user_rules_values);
    print "new resposne is: \n"
    print new_response.to_json
    print "\n------------------\n"
  end

end
