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
# POST /accounts
#
# Body    {"data":{"type":"accounts","attributes":{"name":"John Doe","nickname":"john_doe","password":"secret","passwordConfirmation":"secret"}}}
# Returns 200 on successful registration
#         400 if body is invalid
###
post '/accounts/?' do
  content_type :json

  request.body.rewind 
  body = JSON.parse(request.body.read)
  data = body['data']
  attributes = data['attributes']

  ###
  # Validate request
  ###

  rewrite_url = request.env['HTTP_X_REWRITE_URL']
  error('X-Rewrite-URL header is missing') if rewrite_url.nil?

  error('Incorrect type. Type must be accounts') if data['type'] != 'accounts'

  error('Nickname might not be blank') if attributes['nickname'].nil? or attributes['nickname'].empty?
  
  result = select_account_by_nickname(attributes['nickname'])
  error('Nickname already exists') if not result.empty?

  error('Password might not be blank') if attributes['password'].nil? or attributes['password'].empty?
  error('Password and password confirmation do not match') if attributes['password'] != attributes['passwordConfirmation']


  ###
  # Hash user password with custom salt
  ###

  account_salt = SecureRandom.hex
  hashed_password = (Digest::MD5.new << attributes['password'] + settings.salt + account_salt).hexdigest


  ###
  # Create user and account
  ###

  user_id = SecureRandom.uuid
  account_id = SecureRandom.uuid
  create_user_and_account(user_id, attributes['name'], account_id, attributes['nickname'], hashed_password, account_salt)


  status 201
  {
    data: {
      type: 'accounts',
      id: account_id,
      attributes: {
        name: attributes['name'],
        nickname: attributes['nickname'].downcase
      },
      links: {
        self: rewrite_url.chomp('/') + '/' + account_id
      }
   }
  }.to_json

end


###
# DELETE /accounts/:id
#
# Returns 200 on successful unregistration
#         404 if account with given id doesn't exist
###
delete '/accounts/:id/?' do
  content_type :json


  ###
  # Validate account id
  ###

  result = select_account_by_id(params['id'], false)
  halt 404 if result.empty? # no account with given identifier
  account = result.first

  ### 
  # Update account status
  ###

  update_account_status(account[:uri], MU['account/status/inactive'])

  status 204

end



###
# PATCH /accounts/:id
#
# Body    {"data":{"type":"accounts","id":"1","attributes":{"nickname":"john_doe","password":"newsecret"}}}
# Returns 200 on successful update
#         400 if account is inactive
#         400 if nickname is not unique
###
patch '/accounts/:id/?' do
  content_type :json

  request.body.rewind 
  body = JSON.parse request.body.read
  data = body['data']
  attributes = data['attributes']


  ###
  # Validate body
  ###
  error('Incorrect type. Type must be accounts') if data['type'] != 'accounts'
  error('Incorrect id. Id does not match the request URL.') if data['id'] != params['id']

  result = select_account_by_id(data['id'])
  halt 404 if result.empty? # no active account with given id
  account = result.first

  unless attributes['nickname'].nil?
    result = select_account_by_nickname(attributes['nickname']) 
    error('Nickname already exists') if not result.empty? and result.first[:uri] != account[:uri] # another account with the given nickname already exists
  end

  error('User name cannot be updated') if not attributes['name'].nil?


  ###
  # Hash and store new user password with custom salt
  ###

  unless attributes['password'].nil?
    account_salt = SecureRandom.hex
    hashed_password = (Digest::MD5.new << attributes['password'] + settings.salt + account_salt).hexdigest
    update_account(account[:uri], hashed_password, account_salt, attributes['nickname'])
  end


  status 204
end


###
# Helpers
###

helpers do

  def create_user_and_account(user_id, name, account_id, nickname, hashed_password, account_salt)
    user_uri = settings.graph + "/users/" + user_id 
    account_uri = settings.graph + "/accounts/" + account_id 
    now = DateTime.now.xmlschema

    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{user_uri}> a <#{FOAF.Person}> ;"
    query += "                   <#{FOAF.name}> \"#{name}\" ;"
    query += "                   <#{FOAF.account}> <#{account_uri}> ;"
    query += "                   <#{MU.uuid}> \"#{user_id}\" ;"
    query += "                   <#{DC.created}> \"#{now}\"^^xsd:dateTime ;"
    query += "                   <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "     <#{account_uri}> a <#{FOAF.OnlineAccount}> ;"
    query += "                      <#{FOAF.accountName}> \"#{nickname.downcase}\" ;"
    query += "                      <#{MU.uuid}> \"#{account_id}\" ;"
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
    query =  " SELECT ?uri FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{FOAF.OnlineAccount}> ;"
    query += "          <#{FOAF.accountName}> '#{nickname.downcase}' . "
    query += " }"
    settings.sparql_client.query query  
  end

  def select_account_by_id(id, filter_active = true)
    query =  " SELECT ?uri FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{FOAF.OnlineAccount}> ;"
    query += "          <#{MU['account/status']}> <#{MU['account/status/active']}> ;" if filter_active
    query += "          <#{MU.uuid}> '#{id}' . "
    query += " }"
    settings.sparql_client.query query  
  end

  def update_account(account_uri, hashed_password, account_salt, nickname)
    # Delete old password and salt
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{account_uri}> "
    unless hashed_password.nil? or account_salt.nil?
      query += "                  <#{MU['account/password']}> ?password ;"
      query += "                  <#{MU['account/salt']}> ?salt ;"
    end
    unless nickname.nil?
      query += "                  <#{FOAF.accountName}> ?nickname ;"
    end
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    query += " WHERE {"
    query += "   <#{account_uri}> "
    unless hashed_password.nil? or account_salt.nil?
      query += "                  <#{MU['account/password']}> ?password ;"
      query += "                  <#{MU['account/salt']}> ?salt ;"
    end
    unless nickname.nil?
      query += "                  <#{FOAF.accountName}> ?nickname ;"
    end
    query += "                    <#{DC.modified}> ?modified ."
    query += " }"
    settings.sparql_client.update(query)

    # Insert new password and salt
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{account_uri}> "
    unless hashed_password.nil? or account_salt.nil?
      query += "                    <#{MU['account/password']}> \"#{hashed_password}\" ;"
      query += "                    <#{MU['account/salt']}> \"#{account_salt}\" ;"
    end
    unless nickname.nil?
      query += "                    <#{FOAF.accountName}> \"#{nickname.downcase}\" ;"
    end
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

  def error(title, status = 400)
    halt status, { errors: [{ title: title }] }.to_json
  end

end
