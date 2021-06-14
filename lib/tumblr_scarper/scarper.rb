# frozen_string_literal: true

require 'tumblr_scarper/api_token_hash'
require 'tumblr_client'

require 'fileutils'
require 'json'
require 'yaml'

module TumblrScarper
  # Scarp down the image data from a tumblr blog/post/tag into cached paginated data files
  class Scarper
    include FileUtils::Verbose
    def initialize(options) # rubocop:disable Metrics/MethodLength
      @options = options
      @log = @options.log

      api_token_hash = TumblrScarper::ApiTokenHash.new.api_token_hash

      raise 'No api tokens found; create a `.tumblr` file or run get-tumblr-oauth-token' if api_token_hash.empty?

      Tumblr.configure do |config|
        config.consumer_key = api_token_hash[:consumer_key]
        config.consumer_secret = api_token_hash[:consumer_secret]
        config.oauth_token = api_token_hash[:access_token]
        config.oauth_token_secret = api_token_hash[:access_secret]
      end

      @client = Tumblr::Client.new
    end

    def fetch_tumblr_posts(blog, args)
      @client.posts(blog, args)
    rescue Faraday::ConnectionFailed => e
      @log.fatal e.message
      @log.debug e.backtrace
      raise('ERROR: connection to Tumblr API failed!')
    end

    def write_raw_api_result_cache(data, cache_dir, cache_name, cache_label)
      api_cache_file = File.join(cache_dir, "raw-api-results-offset-#{cache_name}.json")
      @log.info("SCARP: == cached **raw** API results #{cache_label}")
      File.open(api_cache_file, 'w') { |f| f.puts JSON.pretty_generate(data) }
    end

    def scarp(target) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
      blog = target[:blog]
      limit = @options[:batch_size]
      offset = @options[:offset] || 0
      delay = @options[:delay] || 2
      args = target.dup.to_h.reject! { |k| k.to_s =~ /\A(blog)\Z/ }
      args.merge!(limit: limit, offset: offset) #, npf: true)

      cache_dir = @options[:target_cache_dirs][target]

      mkdir_p cache_dir

      results = fetch_tumblr_posts(blog, args)
      total_posts = results['total_posts'] || \
        raise("ERROR: total posts is empty (\n  blog: '#{blog}'\n  results: #{results}\n  args: #{args}\n)")
      total_posts_w = total_posts.to_s.size
      actual_post_count = 0

      if @options[:cache_raw_api_results]
        cache_label = 'initial_fetch'
        api_cache_file = File.join(cache_dir, "raw-api-results-#{cache_label}.json")
        write_raw_api_result_cache(results, cache_dir, cache_label, cache_label) if @options[:cache_raw_api_results]
      end

      posts = nil
      break_loop = false
      loop do # rubocop:disable Metrics/BlockLength
        if (offset + limit) < total_posts
          max = offset + limit - 1
        else
          max = total_posts
          break_loop = true
        end

        cache_name  = offset.to_s.rjust(total_posts_w, '0').gsub(' ', '_')
        cache_file  = File.join(cache_dir, "offset-#{cache_name}.json")
        cache_label = "#{offset}..#{max}/#{total_posts} [#{target}]"

        unless File.file? cache_file
          results = @client.posts(blog, args.merge(limit: limit, offset: offset)) if posts
          posts = results['posts']
          require 'pry'; binding.pry unless posts.size # rubocop:disable Style/Semicolon, Lint/Debugger
          actual_post_count += posts.size
          File.open(cache_file, 'w') { |f| f.puts JSON.pretty_generate(posts) }
          @log.success "SCARP: == cached #{cache_label} posts: #{posts.size} count: #{actual_post_count}"
          write_raw_api_result_cache(results, cache_dir, cache_name, cache_label) if @options[:cache_raw_api_results]

          sleep delay
        else
          @log.happy "SCARP: -- skipping (already in cache) #{cache_label}"
        end


        break if break_loop

        offset += limit
      end
      @log.info "SCARP: == retreived metadata for #{actual_post_count} posts"

      cache_dir
    end
  end
end
