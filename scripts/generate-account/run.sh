#!/usr/bin/env ruby
require 'bundler/inline'
require 'securerandom'
require 'date'
require 'bcrypt'

$stdout.sync = true

puts
puts "This script will generate a new user and account."
puts "Enter the required information. Just hit enter to accept the default value."
puts

print "Person full name: "
STDOUT.flush
person_name = STDIN.gets.chomp

print "Account name: "
STDOUT.flush
account_name = STDIN.gets.chomp

print "Password: "
STDOUT.flush
password = STDIN.gets.chomp

default_salt = ""
print "Application salt (default: none): "
STDOUT.flush
application_salt = STDIN.gets.chomp
application_salt = default_salt if application_salt.empty?

default_domain = "http://ext.data.gift"
print "Resource domain (default: #{default_domain}): "
STDOUT.flush
domain = STDIN.gets.chomp
domain = default_domain if domain.empty?

account_salt = SecureRandom.hex
person_uuid = SecureRandom.uuid
account_uuid = SecureRandom.uuid
hashed_password = BCrypt::Password.create(password + application_salt + account_salt)
now = DateTime.now.xmlschema

query = %(
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX people: <#{domain}/people/>
PREFIX accounts: <#{domain}/accounts/>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX mu:      <http://mu.semte.ch/vocabularies/core/>
PREFIX account: <http://mu.semte.ch/vocabularies/account/>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

INSERT DATA {
   GRAPH <http://mu.semte.ch/graphs/users> {
     people:#{person_uuid} a foaf:Person ;
                   foaf:name "#{person_name}" ;
                   foaf:account accounts:#{account_uuid} ;
                   mu:uuid "#{person_uuid}" ;
                   dcterms:created "#{now}"^^xsd:datetime ;
                   dcterms:modified "#{now}"^^xsd:datetime .
     accounts:#{account_uuid} a foaf:OnlineAccount ;
                   foaf:accountName "#{account_name}" ;
                   mu:uuid "#{account_uuid}" ;
                   account:password """#{hashed_password}""" ;
                   account:salt "#{account_salt}" ;
                   account:status <http://mu.semte.ch/vocabularies/account/status/active> ;
                   dcterms:created "#{now}"^^xsd:datetime ;
                   dcterms:modified "#{now}"^^xsd:datetime .
    }
}
)

timestamp = DateTime.now.strftime("%Y%m%d%H%M%L")
filename = "#{timestamp}-create-user-#{account_name.gsub(/\s|\./, "-")}.sparql"
puts
puts "Copy the following contents to ./config/migrations/#{filename}"
puts
puts query
