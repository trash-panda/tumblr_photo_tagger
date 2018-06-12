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

    def scarp_label(blog, tag=nil, type = nil)
      scarp_label = blog
      scarp_label += "/#{tag}" if tag
      scarp_label += "/#{type}" if type
      scarp_label
    end
    def scarp(blog, tag=nil, type = nil, limit = 20, offset = 0 )
      args       = {}
      args[:tag] = tag if tag
      args[:type] = type if type

      scarp_label = scarp_label(blog,tag,type)
      cache_path = File.expand_path("#{scarp_label}", @cache_dir_root)

      mkdir_p cache_path

      results =  @client.posts(blog, args.merge(limit: limit, offset: offset))
      total_posts   = results['total_posts']
      total_posts_w = total_posts.to_s.size
      actual_post_count = 0

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
          posts = results['posts']
          actual_post_count += posts.size
          File.open(cache_file,'w'){|f| f.puts posts.to_json}
          puts "== cached #{cache_label} posts: #{posts.size} count:" + \
            " #{actual_post_count}"
        end
        break if break_loop
        offset += limit
      end
      puts "== retreived metadata for #{actual_post_count} posts"

      cache_path
    end

  end
end

