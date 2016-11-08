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

    config.middleware.use "MoesifMiddleware", moesif_options

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

Optional. Proc. To help make data analysis easier, identify a user_id from the data.  

```

identify_user = Proc.new {

}
