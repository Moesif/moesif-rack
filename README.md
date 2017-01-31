# Moesif Middleware for Ruby on Rails and Rack

Rack Middleware that logs _incoming_ API calls to Moesif for advanced error analysis for apps built on Ruby on Rails / Rack.

[Source Code on GitHub](https://github.com/moesif/moesif-rack)

[Ruby Gem](https://rubygems.org/gems/moesif_rack)

## How to install

```bash
gem install moesif_rack
```

## How to use

### Create the options

```ruby
moesif_options = {
  'application_id' => 'Your application Id'
}
```

Your can find your Application Id from [_Moesif Dashboard_](https://www.moesif.com/) -> _Top Right Menu_ -> _App Setup_

### Add to middleware

within `config/application.rb`

```ruby


  class Application < Rails::Application
    # snip

    config.middleware.use "MoesifRack::MoesifMiddleware", moesif_options

    # snip
  end

```


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

For details for the spec of event model, please see the [moesifapi-ruby git](https://github.com/Moesif/moesifapi-ruby)

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


## Other integrations

To view more more documentation on integration options, please visit __[the Integration Options Documentation](https://www.moesif.com/docs/getting-started/integration-options/).__
