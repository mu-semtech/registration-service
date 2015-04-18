require 'sinatra'
require 'sparql/client'
require 'json'
require 'digest'
require 'securerandom'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
  set :graph, ENV['MU_APPLICATION_GRAPH']
  set :sparql_client, SPARQL::Client.new('http://localhost:8890/sparql') 
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
  
  query =  " SELECT ?accountName FROM <#{settings.graph}> WHERE {"
  query += "   ?account a <#{FOAF.OnlineAccount}> ;"
  query += "              <#{FOAF.accountName}> '#{data['nickname'].downcase}' . "
  query += " }"
  result = settings.sparql_client.query query  
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
  now = DateTime.now.xmlschema

  query =  " INSERT DATA {"
  query += "   GRAPH <#{settings.graph}> {"
  query += "     <#{user_uri}> a <#{FOAF.Person}> ;"
  query += "                   <#{FOAF.name}> \"#{data['name']}\" ;"
  query += "                   <#{FOAF.account}> <#{account_uri}> ;"
  query += "                   <#{DC.created}> \"#{now}\"^^xsd:dateTime ;"
  query += "                   <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
  query += "     <#{account_uri}> a <#{FOAF.OnlineAccount}> ;"
  query += "                      <#{FOAF.accountName}> \"#{data['nickname'].downcase}\" ;"
  query += "                      <#{MU['account/password']}> \"#{hashed_password}\" ;"
  query += "                      <#{MU['account/salt']}> \"#{account_salt}\" ;"
  query += "                      <#{MU['account/status']}> \"#{MU['account/status/active']}\" ;"
  query += "                      <#{DC.created}> \"#{now}\"^^xsd:dateTime ;"
  query += "                      <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
  query += "   }"
  query += " }"
  settings.sparql_client.update(query)


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

  query =  " SELECT ?uri ?password ?salt FROM <#{settings.graph}> WHERE {"
  query += "   ?uri a <#{FOAF.OnlineAccount}> ;"
  query += "        <#{FOAF.accountName}> '#{data['nickname'].downcase}' ; "
  query += "        <#{MU['account/password']}> ?password ; "
  query += "        <#{MU['account/salt']}> ?salt . "
  query += " }"
  result = settings.sparql_client.query query

  halt 400 if result.empty? # no account with given nickname

  account = result.first
  db_password = account[:password].to_s
  password = Digest::MD5.new << data['password'] + settings.salt + account[:salt].to_s

  halt 400 unless db_password == password.hexdigest # incorrect password given


  ### 
  # Remove old account state
  ###

  query =  " WITH <#{settings.graph}> "
  query += " DELETE {"
  query += "   <#{account[:uri]}> <#{MU['account/status']}> ?status ;"
  query += "                      <#{DC.modified}> ?modified ."
  query += " }"
  query += " WHERE {"
  query += "   <#{account[:uri]}> <#{MU['account/status']}> ?status ;"
  query += "                      <#{DC.modified}> ?modified ."
  query += " }"
  settings.sparql_client.update(query)


  ###
  # Mark account as inactive
  ###

  now = DateTime.now.xmlschema

  query =  " INSERT DATA {"
  query += "   GRAPH <#{settings.graph}> {"
  query += "     <#{account[:uri]}> <#{MU['account/status']}> <#{MU['account/status/inactive']}> ;"
  query += "                        <#{DC.modified}> \"#{now}\"^^xsd:dateTime ."
  query += "   }"
  query += " }"
  settings.sparql_client.update(query)

  status 200

end


