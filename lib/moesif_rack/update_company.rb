class CompanyHelper
    def update_company(api_controller, debug, company_profile)
        if company_profile.any?
            if company_profile.key?("company_id")
                begin
                api_controller.update_company(MoesifApi::CompanyModel.from_hash(company_profile))
                if debug
                    puts "Update Company Successfully"
                end
                rescue MoesifApi::APIException => e
                if e.response_code.between?(401, 403)
                    puts "Unathorized accesss updating company to Moesif. Please verify your Application Id."
                end
                if debug
                    puts "Error updating company to Moesif, with status code: "
                    puts e.response_code
                end
                end
            else 
                puts "To update a company, a company_id field is required"
            end
            else 
            puts "Expecting the input to be of the type - dictionary while updating user"
        end
    end

    def update_companies_batch(api_controller, debug, company_profiles)
        companyModels = []
        company_profiles.each { |company| 
        if company.key?("company_id")
            companyModels << MoesifApi::CompanyModel.from_hash(company)
        else 
            puts "To update a company, a company_id field is required"
        end
        }

        if companyModels.any?
            begin
                api_controller.update_companies_batch(companyModels)
                if debug
                puts "Update Companies Successfully"
                end
            rescue MoesifApi::APIException => e
                if e.response_code.between?(401, 403)
                puts "Unathorized accesss updating companies to Moesif. Please verify your Application Id."
                end
                if debug
                puts "Error updating companies to Moesif, with status code: "
                puts e.response_code
                end
            end
        else
        puts "Expecting the input to be of the type - Array of hashes while updating companies in batch"
        end
    end
end
