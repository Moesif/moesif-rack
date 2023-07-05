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


    result = @goverance_rule_manager.get_applicable_regex_rules(request_fields, request_body)
    print "\nFound applicable regex rule-------\n"
    print result.to_s
    print "\n-------------\n"
    assert(result.length === 1, "expect to get at least one regex rule")
  end


  def test_get_applicable_user_rules_for_unidentified_user
    request_fields = {
      'request.route' => "test/no_italy",
    }
    request_body = {
      "subject" => "should_block"
    }
    result = @goverance_rule_manager.get_applicable_user_rules_for_unidentified_user(request_fields, request_body)
    print "\nFound applicable rule for anonymous user-------\n"
    print result.to_s
    print "\n-------------\n"
    assert(result.length === 2, "expect to get at least one regex rule")
  end


end
