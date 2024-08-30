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

    def fetch_tumblr_likes(blog, args)
      @client.blog_likes(blog, args)
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
      blog = target[:blog] || target[:likes]
      limit = @options[:batch_size]
      offset = @options[:offset] || 0
      delay = @options[:delay] || 2
      args = target.dup.to_h.reject { |k| k.to_s =~ /\A(blog|likes)\Z/ }

      args.merge!(limit: limit, offset: offset) #, npf: true)
      cache_dir = @options[:target_cache_dirs][target]
      mkdir_p cache_dir

      if target[:likes]
        results = fetch_tumblr_likes(target[:likes], args)
        posts_key = 'liked_posts'
        total_posts_key = 'liked_count'
      else
        results = fetch_tumblr_posts(blog, args)
        posts_key = 'posts'
        total_posts_key = 'total_posts'
      end

      total_posts = results[total_posts_key] || \
        raise("ERROR: #{total_posts_key} is empty (\n  blog: '#{blog}'\n  results: #{results}\n  args: #{args}\n)")
      total_posts_w = total_posts.to_s.size
      actual_post_count = 0
      if @options[:cache_raw_api_results]
        cache_label = 'initial_fetch'
        api_cache_file = File.join(cache_dir, "raw-api-results-#{cache_label}.json")
        write_raw_api_result_cache(results, cache_dir, cache_label, cache_label) if @options[:cache_raw_api_results]
      end

      prev_posts = nil
      posts = nil
      break_loop = false
      retry_sleep_wait = 0
      prev_results__links = nil
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
          offset_args = {limit: limit, offset: offset} # og offset pagination
          if prev_results__links # v2 offset pagination
            offset_args = prev_results__links.dig('next','query_params').map{|k,v| [k.to_sym, v] }.to_h
          end
          if target[:likes]
            results = fetch_tumblr_likes(blog, args.merge(offset_args)) if posts
          else 
            @log.warn("Regression check for post offset_args:\n\n#{offset_args.to_yaml}\n\n(TODO: remove after verifying prev_result__links works here)")
            require 'pry'; binding.pry
            results = fetch_tumblr_posts(blog, args.merge(offset_args)) if posts
          end

          

          #results = @client.posts(blog, args.merge(limit: limit, offset: offset)) if posts
          write_raw_api_result_cache(results, cache_dir, cache_name, cache_label) if @options[:cache_raw_api_results]

          posts = results[posts_key]
          posts.map!{|x| x['___scarper::liked'] = true; x } if target[:likes]
          prev_results__links = results['_links']

          if prev_posts && posts == prev_posts
            @log.error('API returned identical results from last query!')
            require 'pry'; binding.pry
            retry_sleep_wait += 10
            @log.warn("sleeping #{delay + retry_sleep_wait} seconds to retry")
            sleep delay + retry_sleep_wait
            next
          end

          # TODO Is the case for this pry still relevant?
          require 'pry'; binding.pry unless (posts && posts.size) # rubocop:disable Style/Semicolon, Lint/Debugger
          actual_post_count += posts.size
          File.open(cache_file, 'w') { |f| f.puts JSON.pretty_generate(posts) }
          @log.success "SCARP: == cached #{cache_label} posts: #{posts.size} count: #{actual_post_count}"

          sleep delay
        else
          @log.happy "SCARP: -- skipping (already in cache) #{cache_label}"
        end


        break if break_loop
        prev_posts = posts
        offset += limit
      end
      @log.info "SCARP: == retreived metadata for #{actual_post_count} posts"

      cache_dir
    end
  end
end
