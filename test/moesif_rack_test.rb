require 'test/unit'
require 'rack'
require_relative '../lib/moesif_rack'

class MoesifRackTest < Test::Unit::TestCase
  def setup
    @app = ->(env) { [200, { "Content-Type" => "application/json" }, ["{ \"key\": \"value\"}"]]}
    @options = { 'application_id' => 'Your Application Id',
    'debug' => true,
    'disable_transaction_id' => true}
    @moesif_rack_app = MoesifRack::MoesifMiddleware.new(@app, @options)
  end

  def test_new_calls_to_middleware
    assert_instance_of MoesifRack::MoesifMiddleware, @moesif_rack_app
  end

  def test_update_user
    metadata = JSON.parse('{'\
      '"email": "testrubyapi@user.com",'\
      '"name": "ruby api user",'\
      '"custom": "testdata"'\
    '}')

    user_model = { "user_id" => "testrubyapiuser", 
                   "modified_time" => Time.now.utc.iso8601, 
                   "metadata" => metadata }

    response = @moesif_rack_app.update_user(user_model)
    assert_equal response, nil
  end

def test_update_users_batch
    metadata = JSON.parse('{'\
      '"email": "testrubyapi@user.com",'\
      '"name": "ruby api user",'\
      '"custom": "testdata"'\
    '}')

    user_models = []

    user_model_A = { "user_id" => "testrubyapiuser", 
                   "modified_time" => Time.now.utc.iso8601, 
                   "metadata" => metadata }
    
    user_model_B = { "user_id" => "testrubyapiuser1", 
                    "modified_time" => Time.now.utc.iso8601, 
                    "metadata" => metadata }

    user_models << user_model_A << user_model_B
    response = @moesif_rack_app.update_users_batch(user_models)
    assert_equal response, nil
  end

  def test_log_event
    response = @moesif_rack_app.call(Rack::MockRequest.env_for("https://acmeinc.com/items/42752/reviews"))
    assert_equal response, @app.call(nil)
  end

  def test_get_config
    assert_operator 100, :>=, @moesif_rack_app.get_config(nil)
  end

end