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
    @goverance_rule_manager = GovernanceRules.new(true)
    @api_client = MoesifApi::MoesifAPIClient.new('Your Moesif Application Id')
    @goverance_rule_manager.reload_rules_if_needed(@api_client.api)
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

  def test_get_applicable_user_rules
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
      headers: {},
      body: {
        "foo_bar" => "if not blocked this would show"
      }
    }

    new_response = @goverance_rule_manager.apply_rules_list(applicable_rules, fake_response, config_user_rules_values);
    print "new resposne is: \n"
    print new_response.to_s
    print "\n------------------\n"
  end

end
