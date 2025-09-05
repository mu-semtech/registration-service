require 'bcrypt'
require 'securerandom'
require_relative 'registration_service/helpers.rb'
require_relative 'registration_service/sparql_queries.rb'

configure do
  set :salt, ENV['MU_APPLICATION_SALT'] || ''
  set :auto_login_on_registration, ENV['MU_AUTO_LOGIN_ON_REGISTRATION'] == 'true'
end

###
# Vocabularies
###

MU_ACCOUNT = RDF::Vocabulary.new(MU.to_uri.to_s + 'account/')
MU_SESSION = RDF::Vocabulary.new(MU.to_uri.to_s + 'session/')
REGISTRATION_SERVICE_RESOURCE_BASE = SERVICE_RESOURCE_BASE + 'registration-service/'

###
# POST /accounts
#
# Body    {"data":{"type":"accounts","attributes":{"name":"John Doe","nickname":"john_doe","password":"secret","password-confirmation":"secret"}}}
# Returns 201 on successful registration
#         400 if the session header is missing
#         400 if body is invalid
#         400 if the given nickname already exists
###
post '/accounts/?' do
  content_type 'application/vnd.api+json'

  data = @json_body['data']
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
# DELETE /accounts/current
#
# Returns 204 on successful unregistration of the current account
#         400 if session header is missing or session header is invalid
###
delete '/accounts/current/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?


  ###
  # Get account
  ###

  result = select_account_id_by_session(session_uri)
  error('Invalid session') if result.empty?
  account_id = result.first[:id].to_s

  delete_account(account_id)

end



###
# DELETE /accounts/:id
#
# This function will be typically used by a system administrator
#
# Returns 204 on successful unregistration
#         404 if account with given id doesn't exist
###
delete '/accounts/:id/?' do
  content_type 'application/vnd.api+json'

  delete_account(params['id'])
end



###
# PATCH /accounts/:id
#
# This function will be typically used by a system administrator
#
# Body    {"data":{"type":"accounts","id":"1","attributes":{"nickname":"john_doe", "password":"anotherSecret"}}}
# Returns 204 on successful update
#         400 if account is inactive
#         400 if nickname is not unique
#         404 if account with given id doesn't exist
###
patch '/accounts/:id/?' do
  content_type 'application/vnd.api+json'

  data = @json_body['data']
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
    error('Nickname already exists') if not result.empty? and result.first[:uri] != account[:uri]
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
# PATCH /accounts/current/changePassword
#
# Body    {"data":{"type":"accounts","id":"current","attributes":{"old-password":"secret", "new-password":"anotherSecret", "new-password-confirmation:"anotherSecret"}}}
# Returns 200 on successful update
#         400 if session header is missing or session header is invalid
#         400 if old password is incorrect
#         400 if new password and new password confirmation do not match
#         400 if account is inactive
###
patch '/accounts/current/changePassword/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?

  ###
  # Validate body
  ###
  data = @json_body['data']
  attributes = data['attributes']

  validate_json_api_content_type(request)
  validate_resource_type('accounts', data)

  error('Password might not be blank') if attributes['new-password'].nil? or attributes['new-password'].empty?
  error('Password and password confirmation do not match') if attributes['new-password'] != attributes['new-password-confirmation']

  ###
  # Get account
  ###

  result = select_account_id_by_session(session_uri)
  error('Invalid session') if result.empty?
  account_id = result.first[:id].to_s

  result = select_account_by_id(account_id)
  error("No active account found with id #{account_id}", 404) if result.empty?
  account = result.first


  ###
  # Validate old password
  ###

  result = select_salted_password_and_salt(account[:uri])
  error("No password and salt found for account #{account[:uri]}.") if result.empty?

  password_and_salt = result.first
  db_password = BCrypt::Password.new password_and_salt[:password].to_s
  password = attributes['old-password'] + settings.salt + password_and_salt[:salt].to_s
  error('Incorrect old password given.') unless db_password == password


  ###
  # Hash and store new user password with custom salt
  ###
  account_salt = SecureRandom.hex
  hashed_password = BCrypt::Password.create attributes['new-password'] + settings.salt + account_salt
  update_password(account[:uri], hashed_password, account_salt)


  status 204

end

###
# Helpers
###

helpers RegistrationService::Helpers
helpers RegistrationService::SparqlQueries
