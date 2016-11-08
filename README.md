MoesifApi Lib for Ruby
======================

[Source Code on GitHub](https://github.com/moesif/moesif-rack)

__Check out Moesif's
[Ruby developer documentation](https://www.moesif.com/developer-documentation) to learn more__



Install from RubyGems
=====================

```bash
gem install moesif_rack
```
How to use:
===========

Create the options

```ruby
moesif_options = {
  'application_id' => 'Your application Id'
}
```

Add to Middleware


within `config/application.rb`

```ruby

module Blog
  class Application < Rails::Application
    # snip

    config.middleware.use "MoesifRack::MoesifMiddleware", moesif_options

    # snip
  end
end

```


How to configure:
=================

options is a hash with these possible key value pairs.

#### application_id

Required. String. this is the id that identifies your app. You can obtain this id from settings
from your [moesif account.](http://www.moesif.com)


#### api_version

Optional. String. Tags the api with version.


#### identify_user

Optional. A Proc that takes env, headers, body and returns a string. To help make data analysis easier, identify a user_id from the data.

```ruby

moesif_options['identify_user'] = Proc.new { |env, headers, body|

  #snip

  'the_user_id'
}

```

@api_version = options['api_version']
@identify_user = options['identify_user']
@identify_session = options['identify_session']
@mask_data = options['mask_data']
@debug = options['debug']

#### identify_session

Optional. A Proc that takes env, headers, body and returns a string.

```ruby

moesif_options['identify_session'] = Proc.new { |env, headers, body|

  #snip

  'the_ession_token'
}

```

#### mask_data

Optional. A Proc that makes an event_model and masks any info that needs to be hidden before sending to Moesif.

```ruby

moesif_options['mask_data'] = Proc.new { |event_model|

  #snip

  event_model
}

```

For details for the spec of event model, please see the [moesifapi-ruby git](https://github.com/Moesif/moesifapi-ruby)


#### debug

Optional. Boolean. If true, it will print out debug messages, also in debug mode, the processing is not done in backend thread.
