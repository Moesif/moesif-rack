# Moesif Middleware for Ruby on Rails and Rack

Rack Middleware that logs API calls built on Ruby on Rails and Rack.

[Source Code on GitHub](https://github.com/moesif/moesif-rack)

__Check out Moesif's
[Ruby developer documentation](https://www.moesif.com/developer-documentation/?ruby) to learn more__

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

### Add to Middleware

within `config/application.rb`

```ruby


  class Application < Rails::Application
    # snip

    config.middleware.use "MoesifRack::MoesifMiddleware", moesif_options

    # snip
  end

```


## Configraution Options

The options is a hash with these possible key value pairs.

#### application_id

Required. String. This is the Moesif application_id under settings
from your [Moesif account.](https://www.moesif.com)


#### api_version

Optional. String. Tag requests with the version of your API.


#### identify_user

Optional.
identify_user is a Proc that takes env, headers, and body as arguments and returns a user_id string. This helps us attribute requests to unique users. Even though Moesif can automatically retrieve the user_id without this, this is highly recommended to ensure accurate attribution.

```ruby

moesif_options['identify_user'] = Proc.new { |env, headers, body|

  #snip

  'the_user_id'
}

```

#### identify_session

Optional. A Proc that takes env, headers, body and returns a string.

```ruby

moesif_options['identify_session'] = Proc.new { |env, headers, body|

  #snip

  'the_session_token'
}

```

#### mask_data

Optional. A Proc that takes event_model as an argument and returns event_model.
With mask_data, you can make modifications to headers or body of the event before it is sent to Moesif.

```ruby

moesif_options['mask_data'] = Proc.new { |event_model|

  #snip

  event_model
}

```

For details for the spec of event model, please see the [moesifapi-ruby git](https://github.com/Moesif/moesifapi-ruby)

#### skip

Optional. A Proc that takes env, headers, body and returns a boolean.

```ruby

moesif_options['skip'] = Proc.new { |env, headers, body|

  #snip

  false
}

```

For details for the spec of event model, please see the [moesifapi-ruby git](https://github.com/Moesif/moesifapi-ruby)


#### debug

Optional. Boolean. Default false. If true, it will print out debug messages. In debug mode, the processing is not done in backend thread.
