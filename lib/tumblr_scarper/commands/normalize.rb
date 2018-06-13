# frozen_string_literal: true

require_relative '../command'
require_relative '../normalizer'

module TumblrScarper
  module Commands
    class Normalize < TumblrScarper::Command
      def initialize(blog, tag, type, cache_dir, options)
        @blog = blog
        @tag = tag
        @type = type
        @cache_dir = cache_dir || Dir.pwd
        @options = options
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        @normalizer = TumblrScarper::Normalizer.new @cache_dir
        path = @normalizer.normalize(@blog,@tag,@type)
        output.puts "OK"
      end
    end
  end
end
