require_relative '../lib/mu/auth-sudo'

USERS_GRAPH = ENV['USERS_GRAPH'] || "http://mu.semte.ch/application"
SESSIONS_GRAPH = ENV['SESSIONS_GRAPH'] || "http://mu.semte.ch/application"

module RegistrationService
  module SparqlQueries

    def create_user_and_account(user_id, name, account_id, nickname, hashed_password, account_salt)
      user_uri = create_user_uri(user_id)
      account_uri = create_account_uri(account_id)
      now = DateTime.now

      query =  " INSERT DATA {"
      query += "   GRAPH <#{USERS_GRAPH}> {"
      query += "     <#{user_uri}> a <#{RDF::Vocab::FOAF.Person}> ;"
      query += "                   <#{RDF::Vocab::FOAF.name}> #{name.sparql_escape} ;"
      query += "                   <#{RDF::Vocab::FOAF.account}> <#{account_uri}> ;"
      query += "                   <#{MU_CORE.uuid}> #{user_id.sparql_escape} ;"
      query += "                   <#{RDF::Vocab::DC.created}> #{now.sparql_escape} ;"
      query += "                   <#{RDF::Vocab::DC.modified}> #{now.sparql_escape} ."
      query += "     <#{account_uri}> a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
      query += "                      <#{RDF::Vocab::FOAF.accountName}> #{nickname.downcase.sparql_escape} ;"
      query += "                      <#{MU_CORE.uuid}> #{account_id.sparql_escape} ;"
      query += "                      <#{MU_ACCOUNT.password}> #{hashed_password.sparql_escape} ;"
      query += "                      <#{MU_ACCOUNT.salt}> #{account_salt.sparql_escape} ;"
      query += "                      <#{MU_ACCOUNT.status}> <#{MU_ACCOUNT['status/active']}> ;"
      query += "                      <#{RDF::Vocab::DC.created}> #{now.sparql_escape} ;"
      query += "                      <#{RDF::Vocab::DC.modified}> #{now.sparql_escape} ."
      query += "   }"
      query += " }"
      Mu::AuthSudo.update(query)
    end

    def remove_old_sessions(session)
      query =  " WITH <#{SESSIONS_GRAPH}> "
      query += " DELETE {"
      query += "   <#{session}> <#{MU_SESSION.account}> ?account ;"
      query += "                <#{MU_CORE.uuid}> ?id . "
      query += " }"
      query += " WHERE {"
      query += "   <#{session}> <#{MU_SESSION.account}> ?account ;"
      query += "                <#{MU_CORE.uuid}> ?id . "
      query += " }"
      Mu::AuthSudo.update(query)
    end

    def select_account_by_nickname(nickname)
      query =  " SELECT ?uri FROM <#{USERS_GRAPH}> WHERE {"
      query += "   ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
      query += "          <#{RDF::Vocab::FOAF.accountName}> #{nickname.downcase.sparql_escape} . "
      query += " }"
      Mu::AuthSudo.query(query)
    end

    def select_account_by_id(id, filter_active = true)
      query =  " SELECT ?uri FROM <#{USERS_GRAPH}> WHERE {"
      query += "   ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
      query += "          <#{MU_ACCOUNT.status}> <#{MU_ACCOUNT['status/active']}> ;" if filter_active
      query += "          <#{MU_CORE.uuid}> #{id.sparql_escape} . "
      query += " }"
      Mu::AuthSudo.query(query)
    end

    def select_account_id_by_session(session)
      query =  " SELECT ?id WHERE {"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {"
      query += "     <#{session}> <#{MU_SESSION.account}> ?account ."
      query += "   }"
      query += "   GRAPH <#{USERS_GRAPH}> {"
      query += "     ?account a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
      query += "              <#{MU_CORE.uuid}> ?id . "
      query += "   }"
      query += " }"
      Mu::AuthSudo.query(query)
    end

    def select_salted_password_and_salt(account_uri)
      query =  " SELECT ?password ?salt FROM <#{USERS_GRAPH}> WHERE {"
      query += "   <#{account_uri}> a <#{RDF::Vocab::FOAF.OnlineAccount}> ; "
      query += "        <#{MU_ACCOUNT.password}> ?password ; "
      query += "        <#{MU_ACCOUNT.salt}> ?salt . "
      query += " }"
      Mu::AuthSudo.query(query)
    end

    def insert_new_session_for_account(account, session_uri, session_id)
      query =  " INSERT DATA {"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {"
      query += "     <#{session_uri}> <#{MU_SESSION.account}> <#{account}> ;"
      query += "                      <#{MU_CORE.uuid}> #{session_id.sparql_escape} ."
      query += "   }"
      query += " }"
      Mu::AuthSudo.update(query)
    end

    def update_account(account_uri, hashed_password, account_salt, nickname)
      # Delete old password and salt
      query =  " WITH <#{USERS_GRAPH}> "
      query += " DELETE {"
      query += "   <#{account_uri}> "
      unless hashed_password.nil? or account_salt.nil?
        query += "                  <#{MU_ACCOUNT.password}> ?password ;"
        query += "                  <#{MU_ACCOUNT.salt}> ?salt ;"
      end
      unless nickname.nil?
        query += "                  <#{RDF::Vocab::FOAF.accountName}> ?nickname ;"
      end
      query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
      query += " }"
      query += " WHERE {"
      query += "   <#{account_uri}> "
      unless hashed_password.nil? or account_salt.nil?
        query += "                  <#{MU_ACCOUNT.password}> ?password ;"
        query += "                  <#{MU_ACCOUNT.salt}> ?salt ;"
      end
      unless nickname.nil?
        query += "                  <#{RDF::Vocab::FOAF.accountName}> ?nickname ;"
      end
      query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
      query += " }"
      Mu::AuthSudo.update(query)

      # Insert new password and salt
      now = DateTime.now
      query =  " INSERT DATA {"
      query += "   GRAPH <#{USERS_GRAPH}> {"
      query += "     <#{account_uri}> "
      unless hashed_password.nil? or account_salt.nil?
        query += "                    <#{MU_ACCOUNT.password}> #{hashed_password.sparql_escape} ;"
        query += "                    <#{MU_ACCOUNT.salt}> #{account_salt.sparql_escape} ;"
      end
      unless nickname.nil?
        query += "                    <#{RDF::Vocab::FOAF.accountName}> #{nickname.downcase.sparql_escape} ;"
      end
      query += "                      <#{RDF::Vocab::DC.modified}> #{now.sparql_escape} ."
      query += "   }"
      query += " }"
      Mu::AuthSudo.update(query)
    end

    def update_password(account_uri, hashed_password, account_salt)
      update_account(account_uri, hashed_password, account_salt, nil)
    end

    def update_account_status(account_uri, status_uri)
      # Delete old status
      query =  " WITH <#{USERS_GRAPH}> "
      query += " DELETE {"
      query += "   <#{account_uri}> <#{MU_ACCOUNT.status}> ?status ;"
      query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
      query += " }"
      query += " WHERE {"
      query += "   <#{account_uri}> <#{MU_ACCOUNT.status}> ?status ;"
      query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
      query += " }"
      Mu::AuthSudo.update(query)

      # Insert new status
      now = DateTime.now
      query =  " INSERT DATA {"
      query += "   GRAPH <#{USERS_GRAPH}> {"
      query += "     <#{account_uri}> <#{MU_ACCOUNT.status}> <#{status_uri}> ;"
      query += "                      <#{RDF::Vocab::DC.modified}> #{now.sparql_escape} ."
      query += "   }"
      query += " }"
      Mu::AuthSudo.update(query)
    end

  end
end
