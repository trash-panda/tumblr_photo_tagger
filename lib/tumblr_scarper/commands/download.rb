# frozen_string_literal: true

require_relative '../command'

module TumblrScarper
  module Commands
    class Download < TumblrScarper::Command
      def initialize(blog, tag, type, cache_dir, options)
        @blog = blog
        @tag = tag
        @type = type
        @cache_dir = cache_dir
        @options = options
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        output.puts "OK"
      end
    end
  end
end
