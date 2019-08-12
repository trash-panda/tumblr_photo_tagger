# frozen_string_literal: true

require_relative '../command'
require_relative '../normalizer'

module TumblrScarper
  module Commands
    class Normalize < TumblrScarper::Command
      def initialize(blog, tag, type, cache_dir, options)
        @args = blog_data_from_arg(blog)
        @tag  = tag || @args[:tag]
        @type = type
        @blog = @args.delete(:blog)
        @cache_dir = cache_dir || Dir.pwd
        @options = options.dup
        @options['accept_tags'] = options['accept_tags'].split(',') if options['accept_tags']
        @options['delete_tags'] = options['delete_tags'].split(',') if options['delete_tags']
        @options['ban_posts_tagged'] = options['ban_posts_tagged'].split(',') if options['ban_posts_tagged']
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        @normalizer = TumblrScarper::Normalizer.new(@cache_dir, @options)
        path = @normalizer.normalize(@blog,@tag,@type)
        output.puts "OK"
      end
    end
  end
end
