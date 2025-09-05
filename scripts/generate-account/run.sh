#!/usr/bin/env ruby
require 'bundler/inline'
require 'securerandom'
require 'date'
require 'bcrypt'
require 'optparse'
require 'fileutils'

$stdout.sync = true

puts ""

options = {
  base_uri: "http://ext.data.gift",
  graph: "http://mu.semte.ch/graphs/users",
  salt: ""
}
OptionParser.new do |opts|
  opts.banner = "Usage: mu script generate-account [options]"

  opts.on("-n", "--name NAME", "Person full name") do |name|
    options[:name] = name
  end

  opts.on("-a", "--account ACCOUNT", "Account name") do |account|
    options[:account] = account
  end

  opts.on("-p", "--password PASSWORD", "Password") do |password|
    options[:password] = password
  end

  opts.on("--graph GRAPH", "Graph to insert the resources in (default: http://mu.semte.ch/graphs/users)") do |graph|
    options[:graph] = graph
  end

  opts.on("--base-uri BASE_URI", "Base URI for resources (default: http://ext.data.gift)") do |base_uri|
    options[:base_uri] = base_uri
  end

  opts.on("--salt APPLICATION_SALT", "Application salt (optional)") do |salt|
    options[:salt] = salt
  end
end.parse!

[:name, :account, :password].each do |key|
  if options[key].nil? || options[key].empty?
    puts "Failed to execute script:"
    puts "  --#{key} is a required option"
    exit(1)
  end
end

account_salt = SecureRandom.hex
person_uuid = SecureRandom.uuid
account_uuid = SecureRandom.uuid
hashed_password = BCrypt::Password.create(options[:password] + options[:salt] + account_salt)
now = DateTime.now.xmlschema

query = %(
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX people: <#{options[:base_uri]}/people/>
PREFIX accounts: <#{options[:base_uri]}/accounts/>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
PREFIX account: <http://mu.semte.ch/vocabularies/account/>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

INSERT DATA {
   GRAPH <#{options[:graph]}> {
     people:#{person_uuid} a foaf:Person ;
                   foaf:name "#{options[:name]}" ;
                   foaf:account accounts:#{account_uuid} ;
                   mu:uuid "#{person_uuid}" ;
                   dcterms:created "#{now}"^^xsd:dateTime ;
                   dcterms:modified "#{now}"^^xsd:dateTime .
     accounts:#{account_uuid} a foaf:OnlineAccount ;
                   foaf:accountName "#{options[:account]}" ;
                   mu:uuid "#{account_uuid}" ;
                   account:password """#{hashed_password}""" ;
                   account:salt "#{account_salt}" ;
                   account:status <http://mu.semte.ch/vocabularies/account/status/active> ;
                   dcterms:created "#{now}"^^xsd:dateTime ;
                   dcterms:modified "#{now}"^^xsd:dateTime .
    }
}
)

migrations_folder = "/data/app/config/migrations"
FileUtils.mkdir_p(migrations_folder)
timestamp = DateTime.now.strftime("%Y%m%d%H%M%S")
filename = "#{timestamp}-create-user-#{options[:account].gsub(/\s|\./, "-")}.sparql"
File.write("#{migrations_folder}/#{filename}", query, encoding: "utf-8")

puts "Migration written to ./config/migrations/#{filename}"
