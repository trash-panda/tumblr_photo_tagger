require 'tumblr_scarper/api_token_hash'
require 'tumblr_client'

require 'fileutils'
require 'json'
require 'yaml'

module TumblrScarper
  class Scarper
    include  FileUtils::Verbose
    attr_accessor :cache_dir
    def initialize(cache_dir=nil)
      api_token_hash = TumblrScarper::ApiTokenHash.new.api_token_hash

      if api_token_hash.empty?
        fail 'No api tokens found; create a `.tumblr` file or run get-tumblr-oauth-token'
      end

      Tumblr.configure do |config|
        config.consumer_key = api_token_hash[:consumer_key]
        config.consumer_secret = api_token_hash[:consumer_secret]
        config.oauth_token = api_token_hash[:access_token]
        config.oauth_token_secret = api_token_hash[:access_secret]
      end

      @client = Tumblr::Client.new
      @cache_dir_root = cache_dir || File.join(Dir.pwd,'tumblr_scarper_cache')
    end

    def scarp(blog, tag=nil, type = nil, limit = 20, offset = 0 )
      args       = {}

      path_paths = blog
      scarp_label = "#{blog}"
      scarp_label += "/#{tag}" if tag
      scarp_label += "/#{type}" if type
      if tag
        args[:tag] = tag
        path_paths  = "#{path_paths}/#{tag}"
      end
      if type
        args[:type] = type
        path_paths  = "#{path_paths}/:w
type}"
      end
      cache_path = File.expand_path("#{path_paths}", @cache_dir_root)
      mkdir_p cache_path

      results =  @client.posts(blog, args.merge(limit: limit, offset: offset))
      total_posts   = results['total_posts']
      total_posts_w = total_posts.to_s.size

      break_loop = false
      loop do
        if ((offset + limit) < total_posts)
          max = offset+limit-1
        else
          max = total_posts
          break_loop = true
        end

        cache_name  = offset.to_s.rjust(total_posts_w,'0').gsub(' ','_')
        cache_file  = File.join(cache_path, "offset-#{cache_name}.json")
        cache_label = "#{offset}..#{max}/#{total_posts} [#{scarp_label}]"

        if File.file? cache_file
          puts "-- skipping (already in cache) #{cache_label}"
        else
          results=@client.posts(blog, args.merge(limit: limit, offset: offset))
          puts "== cached #{cache_label}"
          posts = results['posts']
          File.open(cache_file,'w'){|f| f.puts posts.to_json}
        end

        break if break_loop

        offset += limit
      end

      cache_path
    end

  end
end

