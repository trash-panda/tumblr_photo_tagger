# frozen_string_literal: true

require_relative '../command'
require_relative '../downloader'

module TumblrScarper
  module Commands
    class Download < TumblrScarper::Command
      def initialize(blog, tag, type, cache_dir, download_dir, options)
        @args = blog_data_from_arg(blog)
        @blog = @args.delete(:blog)
        @tag  = tag || @args[:tag]
        @type = type
        @cache_dir = cache_dir || Dir.pwd
        @download_dir = download_dir
        @options = options
      end

      def execute(input: $stdin, output: $stdout)
        # Command logic goes here ...
        @downloader = TumblrScarper::Downloader.new @cache_dir, @download_dir
        path = @downloader.download(@blog,@tag,@type)
        output.puts "OK"
      end
    end
  end
end
