# Moesif Middleware for Ruby on Rails and Rack

[![Built For rack][ico-built-for]][link-built-for]
[![Latest Version][ico-version]][link-package]
[![Total Downloads][ico-downloads]][link-downloads]
[![Software License][ico-license]][link-license]
[![Source Code][ico-source]][link-source]

Rack Middleware that logs _incoming_ API calls to Moesif's AI-powered API analytics service.
Supports Ruby on Rails apps and other Ruby frameworks built on Rack.

[Source Code on GitHub](https://github.com/moesif/moesif-rack)

## How to install

```bash
gem install moesif_rack
```

and if you have a `Gemfile` in your project, please add this line to

```
gem 'moesif_rack', '~> 1.3.2'

```

## How to use

### Create the options

```ruby
moesif_options = {
  'application_id' => 'Your application Id'
}
```

You can find your Application Id from [_Moesif Dashboard_](https://www.moesif.com/) -> _Top Right Menu_ -> _App Setup_

### Add to middleware

within `config/application.rb`

```ruby


  class Application < Rails::Application
    # snip

    config.middleware.use "MoesifRack::MoesifMiddleware", moesif_options

    # snip
  end

```

#### Order of Middleware Matters

Since Moesif Rack is basically a logging middleware, the ordering of middleware matters for accuracy and completeness.
Many middlewares are installed by default by Rails.

To see the list of middlewares that your system already have, type this into the bash.

```bash
  bin/rails middleware
```

The best place for "MoesifRack::MoesifMidleware" is on top as possible (so it captures the data closest to the wire).
Typically, right above the default logger of Rails apps, "Rails::Rack::Logger" is a good spot.
Or if you want to be as close as wire as possible, put it before "ActionDispatch::Static"

You should use the following line of code to insert the middleware into the right spot.

```ruby

config.middleware.insert_before "Rails::Rack::Logger", "MoesifRack::MoesifMiddleware", moesif_options

```

Please note, if you are using "Rack::Deflater" please make sure that "MoesifRack::MoesifMiddlware"
is below it, so it can capture uncompressed data.


## Configuration options

The options is a hash with these possible key value pairs.

#### __`application_id`__

Required. String. This is the Moesif application_id under settings
from your [Moesif account.](https://www.moesif.com)


#### __`api_version`__

Optional. String. Tag requests with the version of your API.


#### __`identify_user`__

Optional.
identify_user is a Proc that takes env, headers, and body as arguments and returns a user_id string. This helps us attribute requests to unique users. Even though Moesif can automatically retrieve the user_id without this, this is highly recommended to ensure accurate attribution.

```ruby

moesif_options['identify_user'] = Proc.new { |env, headers, body|

  #snip

  'the_user_id'
}

```

#### __`identify_company`__

Optional.
identify_company is a Proc that takes env, headers, and body as arguments and returns a company_id string. This helps us attribute requests to unique company.

```ruby

moesif_options['identify_company'] = Proc.new { |env, headers, body|

  #snip

  'the_company_id'
}

```

#### __`get_metadata`__

Optional.
get_metadata is a Proc that takes env, headers, and body as arguments and returns a Hash that is
representation of a JSON object. This allows you to attach any
metadata to this event.

```ruby

moesif_options['get_metadata'] = Proc.new { |env, headers, body|

  #snip
  value = {
      'foo'  => 'abc',
      'bar'  => '123'
  }

  value
}
```

#### __`identify_session`__

Optional. A Proc that takes env, headers, body and returns a string.

```ruby

moesif_options['identify_session'] = Proc.new { |env, headers, body|

  #snip

  'the_session_token'
}

```

#### __`mask_data`__

Optional. A Proc that takes event_model as an argument and returns event_model.
With mask_data, you can make modifications to headers or body of the event before it is sent to Moesif.

```ruby

moesif_options['mask_data'] = Proc.new { |event_model|

  #snip

  event_model
}

```

For details for the spec of event model, please see the [moesifapi-ruby](https://github.com/Moesif/moesifapi-ruby)

#### __`skip`__

Optional. A Proc that takes env, headers, body and returns a boolean.

```ruby

moesif_options['skip'] = Proc.new { |env, headers, body|

  #snip

  false
}

```

For details for the spec of event model, please see the [Moesif Ruby API Documentation](https://www.moesif.com/docs/api?ruby)


#### __`debug`__

Optional. Boolean. Default false. If true, it will print out debug messages. In debug mode, the processing is not done in backend thread.

#### __`capture_outoing_requests`__
Optional. boolean, Default `false`. Set to `true` to capture all outgoing API calls from your app to third parties like Stripe, Github or to your own dependencies while using [Net::HTTP](https://ruby-doc.org/stdlib-2.6.3/libdoc/net/http/rdoc/Net/HTTP.html) package. The options below is applied to outgoing API calls. When the request is outgoing, for options functions that take request and response as input arguments, the request and response objects passed in are [Request](https://www.rubydoc.info/stdlib/net/Net/HTTPRequest) request and [Response](https://www.rubydoc.info/stdlib/net/Net/HTTPResponse) response objects.


##### __`identify_user_outgoing`__

Optional.
identify_user_outgoing is a Proc that takes request and response as arguments and returns a user_id string. This helps us attribute requests to unique users. Even though Moesif can automatically retrieve the user_id without this, this is highly recommended to ensure accurate attribution.

```ruby

moesif_options['identify_user_outgoing'] = Proc.new { |request, response|

  #snip

  'the_user_id'
}

```

##### __`identify_company_outgoing`__

Optional.
identify_company_outgoing is a Proc that takes request and response as arguments and returns a company_id string. This helps us attribute requests to unique company.

```ruby

moesif_options['identify_company_outgoing'] = Proc.new { |request, response|

  #snip

  'the_company_id'
}

```

##### __`get_metadata_outgoing`__

Optional.
get_metadata_outgoing is a Proc that takes request and response as arguments and returns a Hash that is
representation of a JSON object. This allows you to attach any
metadata to this event.

```ruby

moesif_options['get_metadata_outgoing'] = Proc.new { |request, response|

  #snip
  value = {
      'foo'  => 'abc',
      'bar'  => '123'
  }

  value
}
```

##### __`identify_session_outgoing`__

Optional. A Proc that takes request, response and returns a string.

```ruby

moesif_options['identify_session_outgoing'] = Proc.new { |request, response|

  #snip

  'the_session_token'
}

```

##### __`skip_outgoing`__

Optional. A Proc that takes request, response and returns a boolean. If `true` would skip sending the particular event.

```ruby

moesif_options['skip_outgoing'] = Proc.new{ |request, response|

  #snip

  false
}

```

##### __`mask_data_outgoing`__

Optional. A Proc that takes event_model as an argument and returns event_model.
With mask_data_outgoing, you can make modifications to headers or body of the event before it is sent to Moesif.

```ruby

moesif_options['mask_data_outgoing'] = Proc.new { |event_model|

  #snip

  event_model
}

```

## Update User

### update_user method
A method is attached to the moesif middleware object to update the user profile or metadata.
The metadata field can be any custom data you want to set on the user. The `user_id` field is required.

```ruby
metadata = JSON.parse('{'\
      '"email": "testrubyapi@user.com",'\
      '"name": "ruby api user",'\
      '"custom": "testdata"'\
    '}')

user_model = { "user_id" => "testrubyapiuser", 
                "modified_time" => Time.now.utc.iso8601, 
                "metadata" => metadata }

update_user = MoesifRack::MoesifMiddleware.new(@app, @options).update_user(user_model)
```

### update_users_batch method
A method is attached to the moesif middleware object to update the users profile or metadata in batch.
The metadata field can be any custom data you want to set on the user. The `user_id` field is required.

```ruby
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
response = MoesifRack::MoesifMiddleware.new(@app, @options).update_users_batch(user_models)
```

## Update Company

### update_company method
A method is attached to the moesif middleware object to update the company profile or metadata.
The metadata field can be any custom data you want to set on the company. The `company_id` field is required.

```ruby
metadata = JSON.parse('{'\
      '"email": "testrubyapi@company.com",'\
      '"name": "ruby api company",'\
      '"custom": "testdata"'\
    '}')

company_model = { "company_id" => "testrubyapicompany", 
                "metadata" => metadata }

update_company = MoesifRack::MoesifMiddleware.new(@app, @options).update_company(company_model)
```

### update_companies_batch method
A method is attached to the moesif middleware object to update the companies profile or metadata in batch.
The metadata field can be any custom data you want to set on the company. The `company_id` field is required.

```ruby
metadata = JSON.parse('{'\
      '"email": "testrubyapi@user.com",'\
      '"name": "ruby api user",'\
      '"custom": "testdata"'\
    '}')

company_models = []

company_model_A = { "company_id" => "testrubyapicompany",
                "metadata" => metadata }

company_model_B = { "company_id" => "testrubyapicompany1",
                "metadata" => metadata }

company_models << company_model_A << company_model_B
response = MoesifRack::MoesifMiddleware.new(@app, @options).update_companies_batch(company_models)
```

## How to test

1. Manually clone the git repo
2. From terminal/cmd navigate to the root directory of the middleware.
3. Invoke 'gem install moesif_rack'
4. Add your own application id to 'test/moesif_rack_test.rb'. You can find your Application Id from [_Moesif Dashboard_](https://www.moesif.com/) -> _Top Right Menu_ -> _Installation_
5. Invoke 'ruby test/moesif_rack_test.rb'
6. Invoke 'ruby -I test test/moesif_rack_test.rb -n test_capture_outgoing' to test capturing outgoing API calls from your app to third parties like Stripe, Github or to your own dependencies.

## Example Code

[Moesif Rack Example](https://github.com/Moesif/moesif-rack-example) is an example of Moesif Rack applied to an Rail application. Please check it out for reference.

## Other integrations

To view more more documentation on integration options, please visit [the Integration Options Documentation](https://www.moesif.com/docs/getting-started/integration-options/).

[ico-built-for]: https://img.shields.io/badge/built%20for-rack-blue.svg
[ico-version]: https://img.shields.io/gem/v/moesif_rack.svg
[ico-downloads]: https://img.shields.io/gem/dt/moesif_rack.svg
[ico-license]: https://img.shields.io/badge/License-Apache%202.0-green.svg
[ico-source]: https://img.shields.io/github/last-commit/moesif/moesif-rack.svg?style=social

[link-built-for]: https://github.com/rack/rack
[link-package]: https://rubygems.org/gems/moesif_rack
[link-downloads]: https://rubygems.org/gems/moesif_rack
[link-license]: https://raw.githubusercontent.com/Moesif/moesif-rack/master/LICENSE
[link-source]: https://github.com/moesif/moesif-rack
