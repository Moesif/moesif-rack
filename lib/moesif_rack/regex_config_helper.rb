require 'moesif_api'

require_relative './moesif_helpers.rb'

class RegexConfigHelper

    def initialize debug
        @debug = debug
    end

    def prepare_config_mapping(event)
        # Function to prepare config mapping
        # Params:
        #  - event: Event to be logged
        # Return:
        #  - regex_config: Regex config mapping
        regex_config = {}

        # Config mapping for request.verb
        if defined? event.request.verb
            regex_config["request.verb"] = event.request.verb
        end

        # Config mapping for request.uri
        if defined? event.request.uri
            extracted = /http[s]*:\/\/[^\/]+(\/[^?]+)/.match(event.request.uri)
            if !extracted.nil?
              route_mapping = extracted.captures[0]
            else
              route_mapping = '/'
            end
            regex_config["request.route"] = route_mapping
        end

        # Config mapping for request.ip_address
        if defined? event.request.ip_address
            regex_config["request.ip_address"] = event.request.ip_address
        end

        # Config mapping for response.status
        if defined? event.response.status
            regex_config["response.status"] = event.response.status
        end

        return regex_config

    end

    def regex_match(event_value, condition_value)
        # Function to perform the regex matching with event value and condition value
        # Params:
        #  - event_value: Value associated with event (request)
        #  - condition_value: Value associated with the regex config condition
        # Return:
        #  - regex_matched: Regex matched value to determine if the regex match was successful

        extracted = Regexp.new(condition_value).match(event_value)
        if !extracted.nil?
          return extracted.to_s
        end
    end

    def fetch_sample_rate_on_regex_match(regex_configs, config_mapping)
        # Function to fetch the sample rate and determine if request needs to be block or not
        # Args:
        #  - regex_configs: Regex configs
        #  - config_mapping: Config associated with the request
        # Return:
        #  - sample_rate: Sample rate

        # Iterate through the list of regex configs
        regex_configs.each { |regex_rule|
            # Fetch the sample rate
            sample_rate = regex_rule["sample_rate"]
            # Fetch the conditions
            conditions = regex_rule["conditions"]
            # Bool flag to determine if the regex conditions are matched
            regex_matched = false
            # Create a table to hold the conditions mapping (path and value)
            condition_table = {}

            # Iterate through the regex rule conditions and map the path and value
            conditions.each { |condition|
                # Add condition path -> value to the condition table
                condition_table[condition["path"]] = condition["value"]
            }

            # Iterate through conditions table and perform `and` operation between each conditions
            condition_table.each do |path, values|

                # Check if the path exists in the request config mapping
                if !config_mapping[path].nil?
                    # Fetch the value of the path in request config mapping
                    event_data = config_mapping[path]

                    # Perform regex matching with event value
                    regex_matched = regex_match(event_data, values)
                else
                    # Path does not exists in request config mapping, so no need to match regex condition rule
                    regex_matched = false
                end

                # If one of the rule does not match, skip the condition & avoid matching other rules for the same condition
                if !regex_matched
                    break
                end
            end

            # If regex conditions matched, return sample rate
            if regex_matched
                return sample_rate
            end
        }

        # If regex conditions are not matched, return sample rate as None and will use default sample rate
        return nil
    end

end
