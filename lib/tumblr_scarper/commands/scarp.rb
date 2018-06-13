# frozen_string_literal: true

require_relative '../command'
require_relative '../scarper'

module TumblrScarper
  module Commands
    class Scarp < TumblrScarper::Command
      def initialize(blog, tag, type, batch, cache_dir, options)
        @blog = blog
        @tag = tag
        @type = type
        @batch = batch || 20
        @cache_dir = cache_dir || Dir.pwd
        @options = options
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        @scarper = TumblrScarper::Scarper.new @cache_dir
        path = @scarper.scarp(@blog,@tag,@type,@batch)
        output.puts "OK"
      end
    end
  end
end
