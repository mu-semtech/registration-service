require 'bcrypt'
require 'securerandom'
require_relative 'registration_service/helpers.rb'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
  set :auto_login_on_registration, ENV['MU_AUTO_LOGIN_ON_REGISTRATION'] == 'true'
end

###
# Vocabularies
###

MU_ACCOUNT = RDF::Vocabulary.new(MU.to_uri.to_s + 'account/')
MU_SESSION = RDF::Vocabulary.new(MU.to_uri.to_s + 'session/')


###
# POST /accounts
#
# Body    {"data":{"type":"accounts","attributes":{"name":"John Doe","nickname":"john_doe","password":"secret","password-confirmation":"secret"}}}
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

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?
  
  rewrite_url = rewrite_url_header(request)
  error('X-Rewrite-URL header is missing') if rewrite_url.nil?

  validate_resource_type('accounts', data)

  error('Nickname might not be blank') if attributes['nickname'].nil? or attributes['nickname'].empty?
  
  result = select_account_by_nickname(attributes['nickname'])
  error('Nickname already exists') if not result.empty?

  error('Password might not be blank') if attributes['password'].nil? or attributes['password'].empty?
  error('Password and password confirmation do not match') if attributes['password'] != attributes['password-confirmation']


  ###
  # Hash user password with custom salt
  ###

  account_salt = SecureRandom.hex
  hashed_password = BCrypt::Password.create attributes['password'] + settings.salt + account_salt


  ###
  # Create user and account
  ###

  user_id = generate_uuid()
  account_id = generate_uuid()
  create_user_and_account(user_id, attributes['name'], account_id, attributes['nickname'], hashed_password, account_salt)


  if settings.auto_login_on_registration 
    ###
    # Remove old sessions
    ###
    remove_old_sessions(session_uri)
  
    ###
    # Insert new session for new account
    ###
    session_id = generate_uuid()
    account_uri = create_account_uri(account_id)
    insert_new_session_for_account(account_uri, session_uri, session_id)
    update_modified(session_uri)
  end

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
    hashed_password = BCrypt::Password.create attributes['password'] + settings.salt + account_salt
    update_account(account[:uri], hashed_password, account_salt, attributes['nickname'])
  end


  status 204
end


###
# Helpers
###

helpers RegistrationService::Helpers
