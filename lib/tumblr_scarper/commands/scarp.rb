# frozen_string_literal: true

require_relative '../command'
require_relative '../scarper'

module TumblrScarper
  module Commands
    class Scarp < TumblrScarper::Command
      def initialize(blog, tag, type, batch, cache_dir, options)
        @args = blog_data_from_arg(blog)
        @blog = @args.delete(:blog)
        @args[:tag]  = tag || @args[:tag]
        @args[:type] = type
        @batch = batch || 20
        @cache_dir = cache_dir || Dir.pwd
        @options = options
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        @scarper = TumblrScarper::Scarper.new @cache_dir
        path = @scarper.scarp(@blog,@args,@batch)
        output.puts "OK"
      end
    end
  end
end
