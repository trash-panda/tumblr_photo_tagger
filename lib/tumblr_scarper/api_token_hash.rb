require 'yaml'
require 'pry'

module TumblrScarper
  class ApiTokenHash
    YAML_FILE = ENV['TUMBLR_API_YAML_FILE'] || '.tumblr_api_tokens.yaml'

    # the all-caps values are env vars that can be used instead of the yaml file
    API_TOKEN_ENV_MAP = {
      consumer_key:    'TUMBLR_API_CONSUMER_KEY',
      consumer_secret: 'TUMBLR_API_CONSUMER_SECRET',
      access_token:    'TUMBLR_API_ACCESS_TOKEN',
      access_secret:   'TUMBLR_API_ACCESS_SECRET',
    }
    # load from env vars or file if available
    # env vars ovverride yaml file
    def api_token_hash
      @api_token_hash ||= (File.file?(YAML_FILE) ? YAML.load_file(YAML_FILE)|| {} : {})
      API_TOKEN_ENV_MAP.each do |key,var|
        @api_token_hash[key] = ENV[var] if ENV[var]
      end
      @api_token_hash
    end
    def save_api_stuff_to_yaml(hash)
      return if ENV['TUMBLR_API_SAVE'].to_s =~ /^no$/i
      input = ''
      while input.to_s !~ /^(y|yes|n|no)$/i do
        puts "Save API secrets to a local .yaml file [#{YAML_FILE}]? (yes/no)"
        input = gets.strip
      end
      return if input =~ /^(no|n)$/i
      File.open(YAML_FILE,'w'){|f| f.puts hash.to_yaml}
      puts "INFO: Wrote API tokens and secrets to '#{YAML_FILE}'"
    end
  end
end
