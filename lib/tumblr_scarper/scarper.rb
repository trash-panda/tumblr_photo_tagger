require 'tumblr_scarper/api_token_hash'
require 'tumblr_client'

require 'fileutils'
require 'json'
require 'yaml'

module TumblrScarper
  class Scarper
    include  FileUtils::Verbose
    def initialize(options)
      @options = options
      @log = @options.log

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
    end

    def scarp(target)
      blog = target[:blog]
      limit = @options[:batch]
      offset = @options[:offset] || 0
      delay = @options[:delay] || 2
      args = target.dup.to_h.reject!{ |k| k.to_s =~ /\A(blog)\Z/ }
      args.merge!( limit: limit, offset: offset)

      cache_dir = @options[:target_cache_dirs][target]

      mkdir_p cache_dir

      results =  @client.posts(blog, args)

      total_posts   = results['total_posts'] || fail("ERROR: total posts is empty (\n  blog: '#{blog}'\n  results: #{results}\n  args: #{args}\n)")
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
        cache_file  = File.join(cache_dir, "offset-#{cache_name}.json")
        cache_label = "#{offset}..#{max}/#{total_posts} [#{target}]"

        if File.file? cache_file
          puts "-- skipping (already in cache) #{cache_label}"
        else
          results=@client.posts(blog, args.merge(limit: limit, offset: offset))
          posts = results['posts']
          require 'pry'; binding.pry unless posts.size
          actual_post_count += posts.size
          File.open(cache_file,'w'){|f| f.puts posts.to_json}
          puts "== cached #{cache_label} posts: #{posts.size} count:" + \
            " #{actual_post_count}"
          sleep delay
        end
        break if break_loop
        offset += limit
      end
      puts "== retreived metadata for #{actual_post_count} posts"

      cache_dir
    end

  end
end

