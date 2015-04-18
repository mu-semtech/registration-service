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
