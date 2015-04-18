require 'sinatra'
require 'sparql/client'
require 'json'
require 'digest'
require 'securerandom'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
  set :graph, ENV['MU_APPLICATION_GRAPH']
  set :sparql_client, SPARQL::Client.new('http://database:8890/sparql') 
end


###
# Vocabularies
###

include RDF
MU = RDF::Vocabulary.new('http://mu.semte.ch/vocabulary/')


###
# POST /register
#
# Body    { "name": "John Doe", "nickname": "john_doe", "password": "secret", "passwordConfirmation": "secret" }
# Returns 200 on successful registration
#         400 if body is invalid
###
post '/register' do
  content_type :json

  request.body.rewind 
  data = JSON.parse request.body.read


  ###
  # Validate body
  ###

  halt 400, { errors: { title: 'Nickname might not be blank' } }.to_json if data['nickname'].nil? or data['nickname'].empty?
  
  result = select_account_by_nickname(data['nickname'])
  halt 400, { errors: { title: 'Nickname already exists' } }.to_json if not result.empty?

  halt 400, { errors: { title: 'Password might not be blank' } }.to_json if data['password'].nil? or data['password'].empty?
  halt 400, { errors: { title: 'Password and password confirmation do not match' } }.to_json if data['password'] != data['passwordConfirmation']


  ###
  # Hash user password with custom salt
  ###

  account_salt = SecureRandom.hex
  hashed_password = (Digest::MD5.new << data['password'] + settings.salt + account_salt).hexdigest


  ###
  # Create user and account
  ###

  user_uri = settings.graph + "/users/" + SecureRandom.uuid
  account_uri = settings.graph + "/accounts/" + SecureRandom.uuid
  create_user_and_account(user_uri, data['name'], account_uri, data['nickname'], hashed_password, account_salt)


  status 201
  {
   name: data['name'],
   nickname: data['nickname'].downcase
  }.to_json

end


###
# POST /unregister
#
# Body    { "nickname": "john_doe", "password": "secret" }
# Returns 200 on successful unregistration
#         400 if nickname or password is invalid
###
post '/unregister' do
  content_type :json

  request.body.rewind 
  data = JSON.parse request.body.read


  ###
  # Validate login
  ###

  result = select_account_credentials_by_nickname(data['nickname'])
  halt 400 if result.empty? # no account with given nickname

  account = result.first
  db_password = account[:password].to_s
  password = Digest::MD5.new << data['password'] + settings.salt + account[:salt].to_s

  halt 400 unless db_password == password.hexdigest # incorrect password given


  ### 
  # Update account status
  ###

  update_account_status(account[:uri], MU['account/status/inactive'])


  status 200

end



###
# POST /changePassword
#
# Body    { "nickname": "john_doe", "oldPassword": "secret", "newPassword": "anothersecret", "newPasswordConfirmation": "anothersecret" }
# Returns 200 on successful change of password
#         400 if nickname or old password is invalid
#         400 if new passwords don't match
###
post '/changePassword' do
  content_type :json

  request.body.rewind 
  data = JSON.parse request.body.read


  ###
  # Validate body
  ###

  halt 400, { errors: { title: 'New password and password confirmation do not match' } }.to_json if data['newPassword'] != data['newPasswordConfirmation']

  result = select_account_credentials_by_nickname(data['nickname'], MU['account/status/active'])
  halt 400 if result.empty? # no active account with given nickname

  account = result.first
  db_password = account[:password].to_s
  password = Digest::MD5.new << data['oldPassword'] + settings.salt + account[:salt].to_s

  halt 400 unless db_password == password.hexdigest # incorrect old password given


  ###
  # Hash and store new user password with custom salt
  ###

  account_salt = SecureRandom.hex
  hashed_password = (Digest::MD5.new << data['newPassword'] + settings.salt + account_salt).hexdigest
  update_account_credentials(account[:uri], hashed_password, account_salt)

  status 200
end


###
# Helpers
###

helpers do

  def create_user_and_account(user_uri, name, account_uri, nickname, hashed_password, account_salt)
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{user_uri}> a <#{FOAF.Person}> ;"
    query += "                   <#{FOAF.name}> \"#{name}\" ;"
    query += "                   <#{FOAF.account}> <#{account_uri}> ;"
    query += "                   <#{DC.created}> \"#{now}\"^^xsd:dateTime ;"
    query += "                   <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "     <#{account_uri}> a <#{FOAF.OnlineAccount}> ;"
    query += "                      <#{FOAF.accountName}> \"#{nickname.downcase}\" ;"
    query += "                      <#{MU['account/password']}> \"#{hashed_password}\" ;"
    query += "                      <#{MU['account/salt']}> \"#{account_salt}\" ;"
    query += "                      <#{MU['account/status']}> <#{MU['account/status/active']}> ;"
    query += "                      <#{DC.created}> \"#{now}\"^^xsd:dateTime ;"
    query += "                      <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    settings.sparql_client.update(query)
  end

  def select_account_by_nickname(nickname)
    query =  " SELECT ?account FROM <#{settings.graph}> WHERE {"
    query += "   ?account a <#{FOAF.OnlineAccount}> ;"
    query += "              <#{FOAF.accountName}> '#{nickname.downcase}' . "
    query += " }"
    settings.sparql_client.query query  
  end

  def select_account_credentials_by_nickname(nickname, status_uri = nil)
    query =  " SELECT ?uri ?password ?salt FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{FOAF.OnlineAccount}> ;"
    query += "        <#{FOAF.accountName}> '#{nickname.downcase}' ;"
    query += "        <#{MU['account/status']}> <#{status_uri}> ;" unless status_uri.nil?
    query += "        <#{MU['account/password']}> ?password ;"
    query += "        <#{MU['account/salt']}> ?salt ."
    query += " }"
    settings.sparql_client.query query
  end

  def update_account_credentials(account_uri, hashed_password, account_salt)
    # Delete old password and salt
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{account_uri}> <#{MU['account/password']}> ?password ;"
    query += "                    <#{MU['account/salt']}> ?salt ;"
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    query += " WHERE {"
    query += "   <#{account_uri}> <#{MU['account/password']}> ?password ;"
    query += "                    <#{MU['account/salt']}> ?salt ;"
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    settings.sparql_client.update(query)

    # Insert new password and salt
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{account_uri}> <#{MU['account/password']}> \"#{hashed_password}\" ;"
    query += "                      <#{MU['account/salt']}> \"#{account_salt}\" ;"
    query += "                      <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    settings.sparql_client.update(query)
  end

  def update_account_status(account_uri, status_uri)
    # Delete old status
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{account_uri}> <#{MU['account/status']}> ?status ;"
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    query += " WHERE {"
    query += "   <#{account_uri}> <#{MU['account/status']}> ?status ;"
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    settings.sparql_client.update(query)

    # Insert new status
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{account_uri}> <#{MU['account/status']}> <#{status_uri}> ;"
    query += "                      <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    settings.sparql_client.update(query)
  end
end
