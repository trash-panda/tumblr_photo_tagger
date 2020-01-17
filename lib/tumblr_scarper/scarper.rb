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

      begin
        results =  @client.posts(blog, args)
      rescue Faraday::ConnectionFailed => e
        @log.fatal e.message
        @log.debug e.backtrace
        fail( 'ERROR: connection to Tumblr API failed!' )
      end

      total_posts   = results['total_posts'] || fail("ERROR: total posts is empty (\n  blog: '#{blog}'\n  results: #{results}\n  args: #{args}\n)")
      total_posts_w = total_posts.to_s.size
      actual_post_count = 0

      posts = nil
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
        api_cache_file  = File.join(cache_dir, "raw-api-results-offset-#{cache_name}.json")
        cache_label = "#{offset}..#{max}/#{total_posts} [#{target}]"

        if @options[:cache_raw_api_results]
          @log.info("SCARP: == cached **raw** API results #{cache_label}")
          File.open(api_cache_file,'w'){|f| f.puts results.to_json}
        end

        if File.file? cache_file
          @log.happy "SCARP: -- skipping (already in cache) #{cache_label}"
        else
          results=@client.posts(blog, args.merge(limit: limit, offset: offset)) if posts
          posts = results['posts']
          require 'pry'; binding.pry unless posts.size
          actual_post_count += posts.size
          File.open(cache_file,'w'){|f| f.puts posts.to_json}
          @log.success "SCARP: == cached #{cache_label} posts: #{posts.size} count:" + \
            " #{actual_post_count}"
          sleep delay
        end
        break if break_loop
        offset += limit
      end
      @log.info "SCARP: == retreived metadata for #{actual_post_count} posts"

      cache_dir
    end

  end
end

