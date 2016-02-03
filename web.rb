require 'digest'
require 'securerandom'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
end

###
# Vocabularies
###

MU_ACCOUNT = RDF::Vocabulary.new(MU.to_uri.to_s + 'account/')


###
# POST /accounts
#
# Body    {"data":{"type":"accounts","attributes":{"name":"John Doe","nickname":"john_doe","password":"secret","passwordConfirmation":"secret"}}}
# Returns 200 on successful registration
#         400 if body is invalid
###
post '/accounts/?' do
  content_type 'application/vnd.api+json'

  request.body.rewind 
  body = JSON.parse(request.body.read)
  data = body['data']
  attributes = data['attributes']

  ###
  # Validate request
  ###
  validate_json_api_content_type(request)
  error('Id paramater is not allowed', 403) if not data['id'].nil?

  rewrite_url = rewrite_url_header(request)
  error('X-Rewrite-URL header is missing') if rewrite_url.nil?

  validate_resource_type('accounts', data)

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

  user_id = generate_uuid()
  account_id = generate_uuid()
  create_user_and_account(user_id, attributes['name'], account_id, attributes['nickname'], hashed_password, account_salt)


  status 201
  {
    links: {
      self: rewrite_url.chomp('/') + '/' + account_id
    },
    data: {
      type: 'accounts',
      id: account_id,
      attributes: {
        name: attributes['name'],
        nickname: attributes['nickname'].downcase
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
  content_type 'application/vnd.api+json'


  ###
  # Validate account id
  ###

  result = select_account_by_id(params['id'], false)
  error("No active account found with id #{params['id']}", 404) if result.empty?
  account = result.first

  ### 
  # Update account status
  ###

  update_account_status(account[:uri], MU_ACCOUNT['status/inactive'])

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
  content_type 'application/vnd.api+json'

  request.body.rewind 
  body = JSON.parse request.body.read
  data = body['data']
  attributes = data['attributes']


  ###
  # Validate body
  ###
  validate_json_api_content_type(request)
  validate_resource_type('accounts', data)
  error('Incorrect id. Id does not match the request URL.', 409) if data['id'] != params['id']

  result = select_account_by_id(data['id'])
  error("No active account found with id #{data['id']}", 404) if result.empty?
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
    query += "     <#{user_uri}> a <#{RDF::Vocab::FOAF.Person}> ;"
    query += "                   <#{RDF::Vocab::FOAF.name}> \"#{name}\" ;"
    query += "                   <#{RDF::Vocab::FOAF.account}> <#{account_uri}> ;"
    query += "                   <#{MU_CORE.uuid}> \"#{user_id}\" ;"
    query += "                   <#{RDF::Vocab::DC.created}> \"#{now}\"^^xsd:dateTime ;"
    query += "                   <#{RDF::Vocab::DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "     <#{account_uri}> a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
    query += "                      <#{RDF::Vocab::FOAF.accountName}> \"#{nickname.downcase}\" ;"
    query += "                      <#{MU_CORE.uuid}> \"#{account_id}\" ;"
    query += "                      <#{MU_ACCOUNT.password}> \"#{hashed_password}\" ;"
    query += "                      <#{MU_ACCOUNT.salt}> \"#{account_salt}\" ;"
    query += "                      <#{MU_ACCOUNT.status}> <#{MU_ACCOUNT['status/active']}> ;"
    query += "                      <#{RDF::Vocab::DC.created}> \"#{now}\"^^xsd:dateTime ;"
    query += "                      <#{RDF::Vocab::DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    update(query)
  end

  def select_account_by_nickname(nickname)
    query =  " SELECT ?uri FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
    query += "          <#{RDF::Vocab::FOAF.accountName}> '#{nickname.downcase}' . "
    query += " }"
    query(query)
  end

  def select_account_by_id(id, filter_active = true)
    query =  " SELECT ?uri FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ;"
    query += "          <#{MU_ACCOUNT.status}> <#{MU_ACCOUNT['status/active']}> ;" if filter_active
    query += "          <#{MU_CORE.uuid}> '#{id}' . "
    query += " }"
    query(query)
  end

  def update_account(account_uri, hashed_password, account_salt, nickname)
    # Delete old password and salt
    query =  " WITH <#{settings.graph}> "
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
    update(query)

    # Insert new password and salt
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{account_uri}> "
    unless hashed_password.nil? or account_salt.nil?
      query += "                    <#{MU_ACCOUNT.password}> \"#{hashed_password}\" ;"
      query += "                    <#{MU_ACCOUNT.salt}> \"#{account_salt}\" ;"
    end
    unless nickname.nil?
      query += "                    <#{RDF::Vocab::FOAF.accountName}> \"#{nickname.downcase}\" ;"
    end
    query += "                      <#{RDF::Vocab::DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    update(query)
  end

  def update_account_status(account_uri, status_uri)
    # Delete old status
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{account_uri}> <#{MU_ACCOUNT.status}> ?status ;"
    query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
    query += " }"
    query += " WHERE {"
    query += "   <#{account_uri}> <#{MU_ACCOUNT.status}> ?status ;"
    query += "                    <#{RDF::Vocab::DC.modified}> ?modified ."
    query += " }"
    update(query)

    # Insert new status
    now = DateTime.now.xmlschema
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{account_uri}> <#{MU_ACCOUNT.status}> <#{status_uri}> ;"
    query += "                      <#{RDF::Vocab::DC.modified}> \"#{now}\"^^xsd:dateTime ."
    query += "   }"
    query += " }"
    update(query)
  end

end
