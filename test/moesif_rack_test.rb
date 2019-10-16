require 'test/unit'
require 'rack'
require 'net/http'
require_relative '../lib/moesif_rack/app_config.rb'
require_relative '../lib/moesif_rack'

class MoesifRackTest < Test::Unit::TestCase
  def setup
    @app = ->(env) { [200, { "Content-Type" => "application/json" }, ["{ \"key\": \"value\"}"]]}
    @options = { 'application_id' => 'Your Moesif Application Id',
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
      'my_company_id'
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
    @app_config = AppConfig.new
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

    user_model = { "user_id" => "12345", 
                   "company_id" => "67890",
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

    user_model_A = { "user_id" => "12345", 
                   "company_id" => "67890",
                   "modified_time" => Time.now.utc.iso8601, 
                   "metadata" => metadata }
    
    user_model_B = { "user_id" => "1234",
                    "company_id" => "6789", 
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
    @api_client = MoesifApi::MoesifAPIClient.new(@options['application_id'])
    @api_controller = @api_client.api
    @config = @app_config.get_config(@api_controller, @debug)
    @config_etag, @sampling_percentage, @last_updated_time = @app_config.parse_configuration(@config, @debug)
    assert_operator 100, :>=, @sampling_percentage
  end

  def test_update_company
    metadata = JSON.parse('{'\
      '"email": "testrubyapi@company.com",'\
      '"name": "ruby api company",'\
      '"custom": "testdata"'\
    '}')

    company_model = { "company_id" => "12345", 
                      "company_domain" => "acmeinc.com", 
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

    company_model_A = { "company_id" => "12345",
                        "company_domain" => "nowhere.com", 
                   "metadata" => metadata }
    
    company_model_B = { "company_id" => "1234",
                        "company_domain" => "acmeinc.com", 
                    "metadata" => metadata }

    company_models << company_model_A << company_model_B
    response = @moesif_rack_app.update_companies_batch(company_models)
    assert_equal response, nil
  end

end