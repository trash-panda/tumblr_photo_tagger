# frozen_string_literal: true

require 'yaml'
require 'pry'

# rubocop:disable Style/MultilineTernaryOperator
module TumblrScarper
  # API token data structure with read from YAML/ENV and write to YAML
  class ApiTokenHash
    # the all-caps values are env vars that can be used instead of the yaml file
    API_TOKEN_ENV_MAP = {
      consumer_key: 'TUMBLR_API_CONSUMER_KEY',
      consumer_secret: 'TUMBLR_API_CONSUMER_SECRET',
      oauth_token: 'TUMBLR_API_ACCESS_TOKEN',
      oauth_secret: 'TUMBLR_API_ACCESS_SECRET'
    }.freeze

    def initialize
      # by default, we'll use the same file ~/.tumblr file as tumblr_client
      @yaml_file = ENV['TUMBLR_API_YAML_FILE'] || \
        File.file?('.tumblr') ? '.tumblr' : File.expand_path('~/.tumblr')
    end

    # load from env vars or ~/.tumblr file, if available
    # env vars ovverride yaml file
    #
    # returns Hash populated with data if available, or an empty Hash if not
    def api_token_hash
      @api_token_hash ||= begin
        File.file?(@yaml_file) ? YAML.load_file(@yaml_file) || {} : {}
      end
      API_TOKEN_ENV_MAP.each do |key, var|
        @api_token_hash[key] = ENV[var] if ENV[var]
      end
      @api_token_hash
    end

    def save_api_stuff_to_yaml(hash)
      return if ENV['TUMBLR_API_SAVE'].to_s =~ /^no$/i

      input = ''
      while input.to_s !~ /^(y|yes|n|no)$/i
        puts "Save API secrets to a local .yaml file [#{@yaml_file}]? (yes/no)"
        input = gets.strip
      end
      return if input =~ /^(no|n)$/i

      File.open(@yaml_file, 'w') { |f| f.puts hash.to_yaml }
      puts "INFO: Wrote API tokens and secrets to '#{@yaml_file}'"
    end
  end
end
# rubocop:enable Style/MultilineTernaryOperator
