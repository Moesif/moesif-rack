# Moesif Middleware for Ruby on Rails and Rack
by [Moesif](https://moesif.com), the [API analytics](https://www.moesif.com/features/api-analytics) and [API monetization](https://www.moesif.com/solutions/metered-api-billing) platform.

[![Built For rack][ico-built-for]][link-built-for]
[![Latest Version][ico-version]][link-package]
[![Total Downloads][ico-downloads]][link-downloads]
[![Software License][ico-license]][link-license]
[![Source Code][ico-source]][link-source]

Moesif Rack Middleware automatically logs incoming and outgoing API calls 
and sends them to [Moesif](https://www.moesif.com) for API analytics and monitoring.
This middleware allows you to integrate Moesif's API analytics and 
API monetization features into your Ruby applications with minimal configuration. The middleware 
supports Ruby on Rails, Grape, and other Ruby frameworks built on Rack.

> If you're new to Moesif, see [our Getting Started](https://www.moesif.com/docs/) resources to quickly get up and running.

## Prerequisites
Before using this middleware, make sure you have the following:

- [An active Moesif account](https://moesif.com/wrap)
- [A Moesif Application ID](#get-your-moesif-application-id)

### Get Your Moesif Application ID
After you log into [Moesif Portal](https://www.moesif.com/wrap), you can get your Moesif Application ID during the onboarding steps. You can always access the Application ID any time by following these steps from Moesif Portal after logging in:

1. Select the account icon to bring up the settings menu.
2. Select **Installation** or **API Keys**.
3. Copy your Moesif Application ID from the **Collector Application ID** field.
<img class="lazyload blur-up" src="images/app_id.png" width="700" alt="Accessing the settings menu in Moesif Portal">

## Install the Middleware
Install the Moesif gem:

```bash
gem install moesif_rack
```

If you're using Bundler, add the gem to your `Gemfile`:

```ruby
gem 'moesif_rack'
```

Then run `bundle install`.

## Configure the Middleware
See the available [configuration options](#configuration-options) to learn how to configure the middleware for your use case.

## How to use

### 1. Enter Moesif Application ID

Create a hash containing `application_id` and specify your [Moesif Application ID](#get-your-moesif-application-id) as its value. This hash also contains other [options](#configuration-options) you may want to specify.

```ruby
moesif_options = {
  'application_id' => 'YOUR_MOESIF_APPLICATION_ID'
}
```

### 2. Add the Middleware

#### For Rails 5.0 or Newer

Using strings or symbols for middleware class names is deprecated for newer frameworks like Ruby 5.0. So we recommend 
that you pass the class directly:

```ruby
  class Application < Rails::Application
    moesif_options = {
      'application_id' => 'YOUR_MOESIF_APPLICATION_ID'
    }

    config.middleware.use MoesifRack::MoesifMiddleware, moesif_options
  end
```

#### For Rails 4.0 and Other Frameworks

For most Rack-based frameworks including Rails 4.x or older, add the middleware `MoesifRack::MoesifMiddleware` within `config/application.rb`:

```ruby
  class Application < Rails::Application
    moesif_options = {
      'application_id' => 'Your Moesif Application Id'
    }

    config.middleware.use "MoesifRack::MoesifMiddleware", moesif_options
  end
```

#### For Grape API

For [Grape APIs](https://github.com/ruby-grape/grape), you can add the middleware after any custom parsers or formatters.

```ruby
module Acme
  class Ping < Grape::API
    format :json

    moesif_options = {
      'application_id' => 'Your Moesif Application Id'
    }

    insert_after Grape::Middleware::Formatter, MoesifRack::MoesifMiddleware, moesif_options

    get '/ping' do
      { ping: 'pong' }
    end
  end
end
```

#### Order of Middleware

Since Moesif Rack is a logging middleware, the ordering of middleware matters.

The best place for `MoesifRack::MoesifMidleware` is near the top so it captures the data closest to the wire. 
But remember to put it after any body parsers or authentication  middleware.

Typically, right above the default logger of Rails app `Rails::Rack::Logger` is a good spot.
If you want to be as close as wire as possible, put it before `ActionDispatch::Static`.

To insert the Moesif middleware before `Rails::Rack::Logger`, you can use the `insert_before` method instead of 
`use`:

```ruby
  class Application < Rails::Application
    # snip

    config.middleware.insert_before Rails::Rack::Logger, MoesifRack::MoesifMiddleware, moesif_options

    # snip
  end
```

If you are using `Rack::Deflater` or other compression middleware, make sure to put the Moesif middleware after
it so it can capture the uncompressed data.

To see your current list of middleware, execute this command:

```bash
  bin/rails middleware
```
### Optional: Capturing Outgoing API Calls
In addition to your own APIs, you can also start capturing calls out to third party services through by setting the [`capture_outgoing_requests`](#capture_outgoing_requests) option.

For configuration options specific to capturing outgoing API calls, see [Options For Outgoing API Calls](#options-for-outgoing-api-calls).

## Troubleshoot
For a general troubleshooting guide that can help you solve common problems, see [Server Troubleshooting Guide](https://www.moesif.com/docs/troubleshooting/server-troubleshooting-guide/).

Other troubleshooting supports:

- [FAQ](https://www.moesif.com/docs/faq/)
- [Moesif support email](mailto:support@moesif.com)

## Repository Structure

```
.
├── BUILDING.md
├── Gemfile
├── images/
├── lib/
├── LICENSE
├── moesif_capture_outgoing/
├── moesif_rack.gemspec
├── Rakefile
├── README.md
└── test/
```

## Configuration Options
The following sections describe the available configuration options for this middleware. You have to set these options in a Ruby hash as key-value pairs. See the [examples](#examples) for better understanding.

#### `application_id` (Required)
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
  </tr>
  <tr>
   <td>
    String
   </td>
  </tr>
</table>

A string that [identifies your application in Moesif](#get-your-moesif-application-id).

#### `api_version`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
  </tr>
  <tr>
   <td>
    String
   </td>
  </tr>
</table>

Optional.

Use to tag requests with the version of your API.


#### `identify_user`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional, but highly recommended.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the user ID used by your system. 

Moesif identifies users automatically. However, due to the differences arising from different frameworks and implementations, set this option to ensure user identification properly.


```ruby
moesif_options['identify_user'] = Proc.new { |env, headers, body|

  # Add your custom code that returns a string for user id
  '12345'
}
```

#### `identify_company`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the company ID for this event. This helps Moesif attribute requests to unique company.

```ruby

moesif_options['identify_company'] = Proc.new { |env, headers, body|

  # Add your custom code that returns a string for company id
  '67890'
}

```

#### `identify_session`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the session token for this event. 

Similar to users and companies, Moesif tries to retrieve session tokens automatically. But if it doesn't work for your service, use this option to help identify sessions.

```ruby

moesif_options['identify_session'] = Proc.new { |env, headers, body|
    # Add your custom code that returns a string for session/API token
    'XXXXXXXXX'
}
```

#### `get_metadata`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    <code>Hash</code>
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a `Hash` that represents a JSON object. This allows you to attach any
metadata to this event.

```ruby

moesif_options['get_metadata'] = Proc.new { |env, headers, body|
  # Add your custom code that returns a dictionary
  value = {
      'datacenter'  => 'westus',
      'deployment_version'  => 'v1.2.3'
  }
  value
}
```

#### `mask_data`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    <code>EventModel</code>
   </td>
  </tr>
</table>

Optional. 

A Proc that takes an `EventModel` as an argument and returns an `EventModel`.

This option allows you to modify headers or body of an event before sending the event to Moesif.

```ruby

moesif_options['mask_data'] = Proc.new { |event_model|
  # Add your custom code that returns a event_model after modifying any fields
  event_model.response.body.password = nil
  event_model
}

```

For more information and the spec of Moesif's event model, see the source code of [Moesif API library for Ruby](https://github.com/Moesif/moesifapi-ruby).

#### `skip`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    Boolean
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a boolean. Return `true` if you want to skip a particular event.

```ruby

moesif_options['skip'] = Proc.new { |env, headers, body|
  # Add your custom code that returns true to skip logging the API call
  if env.key?("REQUEST_URI") 
      # Skip probes to health page
      env["REQUEST_URI"].include? "/health"
  else
      false
  end
}

```

#### `debug`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    Boolean
   </td>
   <td>
    <code>false</code>
   </td>
  </tr>
</table>

Optional.

If `true`, the middleware prints out debug messages. In debug mode, the processing is not done in backend thread.

#### `log_body`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    Boolean
   </td>
   <td>
    <code>true</code>
   </td>
  </tr>
</table>

Optional.

If `false`, doesn't log request and response body to Moesif.

#### `batch_size`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    <code>int</code>
   </td>
   <td>
    <code>200</code>
   </td>
  </tr>
</table>

Optional.

The maximum batch size when sending to Moesif.

#### `batch_max_time`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    <code>int</code>
   </td>
   <td>
    <code>2</code>
   </td>
  </tr>
</table>

Optional. 

The maximum time in seconds to wait (approximately) before triggering flushing of the queue and sending to Moesif.

#### `event_queue_size`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    <code>int</code>
   </td>
   <td>
    <code>1000000</code>
   </td>
  </tr>
</table>

Optional.

The maximum number of events to hold in queue before sending to Moesif. 

In case of network issues, the middleware may fail to connect or send event to Moesif. In those cases, the middleware skips adding new to event to queue to prevent memory overflow.

### Options For Outgoing API Calls 
The following options apply to outgoing API calls. These are calls you initiate using [`Net::HTTP`](https://ruby-doc.org/stdlib-2.6.3/libdoc/net/http/rdoc/Net/HTTP.html) package to third parties like Stripe or to your own services.

Several options use request and response as input arguments. The request and response objects passed in are [`HTTPRequest`](https://www.rubydoc.info/stdlib/net/Net/HTTPRequest) request and [`HTTPResponse`](https://www.rubydoc.info/stdlib/net/Net/HTTPResponse) response objects.

#### `capture_outgoing_requests`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    Boolean
   </td>
   <td>
    <code>false</code>
   </td>
  </tr>
</table>

Set to `true` to capture all outgoing API calls from your app.

#### `identify_user_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional, but highly recommended.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the user ID used by your system. 

Moesif identifies users automatically. However, due to the differences arising from different frameworks and implementations, set this option to ensure user identification properly.

```ruby

moesif_options['identify_user_outgoing'] = Proc.new { |request, response|

  # Add your custom code that returns a string for user id
  '12345'
}

```

#### `identify_company_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the company ID for this event. This helps Moesif attribute requests to unique company.


```ruby

moesif_options['identify_company_outgoing'] = Proc.new { |request, response|

  # Add your custom code that returns a string for company id
  '67890'
}

```

#### `get_metadata_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    <code>Hash</code>
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a `Hash` that represents a JSON object. This allows you to attach any
metadata to this event.


```ruby

moesif_options['get_metadata_outgoing'] = Proc.new { |request, response|

  # Add your custom code that returns a dictionary
  value = {
      'datacenter'  => 'westus',
      'deployment_version'  => 'v1.2.3'
  }
  value
}
```

#### `identify_session_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    String
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a string that represents the session token for this event. 

Similar to users and companies, Moesif tries to retrieve session tokens automatically. But if it doesn't work for your service, use this option to help identify sessions.

```ruby

moesif_options['identify_session_outgoing'] = Proc.new { |request, response|

    # Add your custom code that returns a string for session/API token
    'XXXXXXXXX'
}

```

#### `skip_outgoing`
<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    Boolean
   </td>
  </tr>
</table>

Optional.

A `Proc` that takes `env`, `headers`, and `body` as arguments.

Returns a boolean. Return `true` if you want to skip a particular event.


```ruby

moesif_options['skip_outgoing'] = Proc.new{ |request, response|

  # Add your custom code that returns true to skip logging the API call
  false
}

```

#### `mask_data_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Return type
   </th>
  </tr>
  <tr>
   <td>
    <code>Proc</code>
   </td>
   <td>
    <code>EventModel</code>
   </td>
  </tr>
</table>

Optional. 

A Proc that takes an `EventModel` as an argument and returns an `EventModel`.

This option allows you to modify headers or body of an event before sending the event to Moesif.

```ruby

moesif_options['mask_data_outgoing'] = Proc.new { |event_model|

  # Add your custom code that returns a event_model after modifying any fields
  event_model.response.body.password = nil
  event_model
}

```

### `log_body_outgoing`

<table>
  <tr>
   <th scope="col">
    Data type
   </th>
   <th scope="col">
    Default
   </th>
  </tr>
  <tr>
   <td>
    Boolean
   </td>
   <td>
    <code>true</code>
   </td>
  </tr>
</table>

Optional.

If `false`, doesn't log request and response body to Moesif.

## Examples

- __[Moesif Rails 5 Example](https://github.com/Moesif/moesif-rails5-example)__: an example of Moesif with a Ruby on Rails 5 application
- __[Moesif Rails 4 Example](https://github.com/Moesif/moesif-rails4-example)__: an example of Moesif with a Ruby on Rails 4 application
- __[Moesif Rack Example](https://github.com/Moesif/moesif-rack-example)__: an example of Moesif in a Rack application

The following examples demonstrate how to add and update customer information.

### Update a Single User
To create or update a [user](https://www.moesif.com/docs/getting-started/users/) profile in Moesif, use the `update_user()` method.

```ruby
metadata = {
  :email => 'john@acmeinc.com',
  :first_name => 'John',
  :last_name => 'Doe',
  :title => 'Software Engineer',
  :salesInfo => {
      :stage => 'Customer',
      :lifetime_value => 24000,
      :accountOwner => 'mary@contoso.com',
  }
}

# Campaign object is optional, but useful if you want to track ROI of acquisition channels
# See https://www.moesif.com/docs/api#users for campaign schema
campaign = MoesifApi::CampaignModel.new()
campaign.utm_source = "google"
campaign.utm_medium = "cpc"
campaign.utm_campaign = "adwords"
campaign.utm_term = "api+tooling"
campaign.utm_content = "landing"

# Only user_id is required.
# metadata can be any custom object
user = MoesifApi::UserModel.new()
user.user_id = "12345"
user.company_id = "67890" # If set, associate user with a company object
user.campaign = campaign
user.metadata = metadata

update_user = MoesifRack::MoesifMiddleware.new(@app, @options).update_user(user_model)
```
The `metadata` field can contain any customer demographic or other info you want to store. Moesif only requires the `user_id` field.

For more information, see the function documentation in [Moesif Ruby API reference](https://www.moesif.com/docs/api?ruby#update-a-user).

### Update Users in Batch
To update a list of [users](https://www.moesif.com/docs/getting-started/users/) in one batch, use the `update_users_batch()` method.

```ruby
users = []

metadata = {
  :email => 'john@acmeinc.com',
  :first_name => 'John',
  :last_name => 'Doe',
  :title => 'Software Engineer',
  :salesInfo => {
      :stage => 'Customer',
      :lifetime_value => 24000,
      :accountOwner => 'mary@contoso.com',
  }
}

# Campaign object is optional, but useful if you want to track ROI of acquisition channels
# See https://www.moesif.com/docs/api#users for campaign schema
campaign = MoesifApi::CampaignModel.new()
campaign.utm_source = "google"
campaign.utm_medium = "cpc"
campaign.utm_campaign = "adwords"
campaign.utm_term = "api+tooling"
campaign.utm_content = "landing"

# Only user_id is required.
# metadata can be any custom object
user = MoesifApi::UserModel.new()
user.user_id = "12345"
user.company_id = "67890" # If set, associate user with a company object
user.campaign = campaign
user.metadata = metadata

users << user

response = MoesifRack::MoesifMiddleware.new(@app, @options).update_users_batch(users)
```

The `metadata` field can contain any customer demographic or other info you want to store. Moesif only requires the `user_id` field. This method is a convenient helper that calls the Moesif API lib.

For more information, see the function documentation in [Moesif Ruby API reference](https://www.moesif.com/docs/api?ruby#update-users-in-batch).

### Update a Single Company
To update a single [company](https://www.moesif.com/docs/getting-started/companies/), use the `update_company()` method.

```ruby
metadata = {
  :org_name => 'Acme, Inc',
  :plan_name => 'Free',
  :deal_stage => 'Lead',
  :mrr => 24000,
  :demographics => {
      :alexa_ranking => 500000,
      :employee_count => 47
  }
}

# Campaign object is optional, but useful if you want to track ROI of acquisition channels
# See https://www.moesif.com/docs/api#update-a-company for campaign schema
campaign = MoesifApi::CampaignModel.new()
campaign.utm_source = "google"
campaign.utm_medium = "cpc"
campaign.utm_campaign = "adwords"
campaign.utm_term = "api+tooling"
campaign.utm_content = "landing"

# Only company_id is required.
# metadata can be any custom object
company = MoesifApi::CompanyModel.new()
company.company_id = "67890"
company.company_domain = "acmeinc.com" # If domain is set, Moesif will enrich your profiles with publicly available info 
company.campaign = campaign
company.metadata = metadata

update_company = MoesifRack::MoesifMiddleware.new(@app, @options).update_company(company_model)
```

The `metadata` field can contain any customer demographic or other info you want to store. Moesif only requires the `company_id` field. This method is a convenient helper that calls the Moesif API lib.

For more information, see the function documentation in [Moesif Ruby API reference](https://www.moesif.com/docs/api?ruby#update-a-company).

### Update Companies in Batch
To update a list of [companies](https://www.moesif.com/docs/getting-started/companies/) in one batch, use the `update_companies_batch()` method.

```ruby
companies = []

metadata = {
  :org_name => 'Acme, Inc',
  :plan_name => 'Free',
  :deal_stage => 'Lead',
  :mrr => 24000,
  :demographics => {
      :alexa_ranking => 500000,
      :employee_count => 47
  }
}

# Campaign object is optional, but useful if you want to track ROI of acquisition channels
# See https://www.moesif.com/docs/api#update-a-company for campaign schema
campaign = MoesifApi::CampaignModel.new()
campaign.utm_source = "google"
campaign.utm_medium = "cpc"
campaign.utm_campaign = "adwords"
campaign.utm_term = "api+tooling"
campaign.utm_content = "landing"

# Only company_id is required.
# metadata can be any custom object
company = MoesifApi::CompanyModel.new()
company.company_id = "67890"
company.company_domain = "acmeinc.com" # If domain is set, Moesif will enrich your profiles with publicly available info 
company.campaign = campaign
company.metadata = metadata

companies << company
response = MoesifRack::MoesifMiddleware.new(@app, @options).update_companies_batch(companies)
```

The `metadata` field can contain any customer demographic or other info you want to store. Moesif only requires the `company_id` field. This method is a convenient helper that calls the Moesif API lib.

For more information, see the function documentation in [Moesif Ruby API reference](https://www.moesif.com/docs/api?ruby#update-companies-in-batch).

## How to Test

1. Manually clone this repository.
2. From your terminal, navigate to the root directory of the middleware.
3. Run `gem install moesif_rack`.
4. Add your [Moesif Application ID](#get-your-moesif-application-id) to `test/moesif_rack_test.rb`.
5. Run `ruby test/moesif_rack_test.rb`.
6. Then run `ruby -I test test/moesif_rack_test.rb -n test_capture_outgoing` to test capturing outgoing API calls from your app to third parties like Stripe, Github or to your own dependencies.

## Explore Other Integrations

Explore other integration options from Moesif:

- [Server integration options documentation](https://www.moesif.com/docs/server-integration//)
- [Client integration options documentation](https://www.moesif.com/docs/client-integration/)

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
