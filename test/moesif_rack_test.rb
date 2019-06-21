require 'test/unit'
require 'rack'
require 'net/http'
require_relative '../lib/moesif_rack'

class MoesifRackTest < Test::Unit::TestCase
  def setup
    @app = ->(env) { [200, { "Content-Type" => "application/json" }, ["{ \"key\": \"value\"}"]]}
    @options = { 'application_id' => 'Your Application Id',
    'debug' => true,
    'disable_transaction_id' => true,
    'capture_outoing_requests' => true,
    'get_metadata' => Proc.new {|request, response|
      {
        'foo'  => 'abc',
        'bar'  => '123'
      }
    },
    'get_metadata_outgoing' => Proc.new {|request, response|
      {
        'foo'  => 'abc',
        'bar'  => '123'
      }
    },
    'identify_user' => Proc.new{|request, response|
      'my_user_id'
    },
    'identify_company' => Proc.new{|request, response|
      '12345'
    },
    'identify_user_outgoing' => Proc.new{|request, response|
      'outgoing_user_id'
    },
    'identify_company_outgoing' => Proc.new{|request, response|
      'outgoing_company_id'
    },
    'identify_session_outgoing' => Proc.new{|request, response|
      'outgoing_session'
    },
    'skip_outgoing' => Proc.new{|request, response|
      false
    },
    'mask_data_outgoing' => Proc.new{|event_model|
      event_model
    }
  }
    @moesif_rack_app = MoesifRack::MoesifMiddleware.new(@app, @options)
  end

  def test_capture_outgoing
    url = URI.parse('https://api.github.com')
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port, :use_ssl => url.scheme == 'https') {|http|
      http.request(req)
    }
    assert_not_equal res, nil
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

  def test_update_company
    metadata = JSON.parse('{'\
      '"email": "testrubyapi@company.com",'\
      '"name": "ruby api company",'\
      '"custom": "testdata"'\
    '}')

    company_model = { "company_id" => "testrubyapicompany", 
                   "metadata" => metadata }

    response = @moesif_rack_app.update_company(company_model)
    assert_equal response, nil
  end

  def test_update_companies_batch
    metadata = JSON.parse('{'\
      '"email": "testrubyapi@company.com",'\
      '"name": "ruby api company",'\
      '"custom": "testdata"'\
    '}')

    company_models = []

    company_model_A = { "company_id" => "testrubyapicompany",
                   "metadata" => metadata }
    
    company_model_B = { "company_id" => "testrubyapicompany1",
                    "metadata" => metadata }

    company_models << company_model_A << company_model_B
    response = @moesif_rack_app.update_companies_batch(company_models)
    assert_equal response, nil
  end

end