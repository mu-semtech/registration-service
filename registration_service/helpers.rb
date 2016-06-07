module RegistrationService
  module Helpers

    def create_user_uri(user_id)
      REGISTRATION_SERVICE_RESOURCE_BASE + "users/" + user_id 
    end

    def create_account_uri(account_id)
      REGISTRATION_SERVICE_RESOURCE_BASE + "accounts/" + account_id 
    end

    def delete_account(account_id)
      ###
      # Validate account id
      ###
      
      result = select_account_by_id(account_id, false)
      error("No account found with id #{params['id']}", 404) if result.empty?
      account = result.first

      ### 
      # Update account status
      ###

      update_account_status(account[:uri], MU_ACCOUNT['status/inactive'])

      status 204
    end

  end
end
