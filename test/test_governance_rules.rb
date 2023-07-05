require 'moesif_api'
require 'test/unit'
require 'rack'
require 'net/http'
require_relative '../lib/moesif_rack/app_config'
require_relative '../lib/moesif_rack'
require_relative '../lib/moesif_rack/governance_rules'

class GovernanceRulesTest < Test::Unit::TestCase
  def setup
    @goverance_rule_manager = GovernanceRules.new(true)
    @api_client = MoesifApi::MoesifAPIClient.new('Moesif application Id')
  end

  def test_load
    @goverance_rule_manager.reload_rules_if_needed(@api_client.api)
    print @goverance_rule_manager.rules
    print @goverance_rule_manager.user_rules
  end
end
