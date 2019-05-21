class UserHelper
    def update_user(api_controller, debug, user_profile)
        if user_profile.any?
            if user_profile.key?("user_id")
            begin
                api_controller.update_user(MoesifApi::UserModel.from_hash(user_profile))
                if debug
                puts "Update User Successfully"
                end
            rescue MoesifApi::APIException => e
                if e.response_code.between?(401, 403)
                puts "Unathorized accesss updating user to Moesif. Please verify your Application Id."
                end
                if debug
                puts "Error updating user to Moesif, with status code: "
                puts e.response_code
                end
            end
            else 
            puts "To update an user, an user_id field is required"
            end
        else 
            puts "Expecting the input to be of the type - dictionary while updating user"
        end
    end

    def update_users_batch(api_controller, debug, user_profiles)
        userModels = []
        user_profiles.each { |user| 
        if user.key?("user_id")
            userModels << MoesifApi::UserModel.from_hash(user)
        else 
            puts "To update an user, an user_id field is required"
        end
        }

        if userModels.any?
            begin
            api_controller.update_users_batch(userModels)
            if debug
                puts "Update Users Successfully"
            end
            rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
                puts "Unathorized accesss updating user to Moesif. Please verify your Application Id."
            end
            if debug
                puts "Error updating user to Moesif, with status code: "
                puts e.response_code
            end
            end
        else
            puts "Expecting the input to be of the type - Array of hashes while updating users in batch"
        end
    end
end
