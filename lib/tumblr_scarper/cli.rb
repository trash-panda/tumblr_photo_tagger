# frozen_string_literal: true

require 'thor'

module TumblrScarper
  # Handle the application command line parsing
  # and the dispatch to various command objects
  #
  # @api public
  class CLI < Thor
    # Error raised by this runner
    Error = Class.new(StandardError)

    desc 'version', 'tumblr_scarper version'
    def version
      require_relative 'version'
      puts "v#{TumblrScarper::VERSION}"
    end
    map %w(--version -v) => :version

    desc 'download BLOG [TAG] [TYPE] [CACHE_DIR] [DOWNLOAD_DIR]', 'Download and tag images from nomalized list'
    method_option :help, aliases: '-h', type: :boolean,
                         desc: 'Display usage information'
    def download(blog, tag = nil, type = nil, cache_dir = nil, download_dir = nil)
      if options[:help]
        invoke :help, ['download']
      else
        require_relative 'commands/download'
        TumblrScarper::Commands::Download.new(blog, tag, type, cache_dir, download_dir, options).execute
      end
    end

    desc 'normalize BLOG [TAG] [TYPE] [CACHE_DIR]', 'Crunch tags and URLs from a scarped blog'
    method_option :help, aliases: '-h', type: :boolean,
                         desc: 'Display usage information'
    def normalize(blog, tag = nil, type = nil, cache_dir = nil)
      if options[:help]
        invoke :help, ['normalize']
      else
        require_relative 'commands/normalize'
        TumblrScarper::Commands::Normalize.new(blog, tag, type, cache_dir, options).execute
      end
    end

    desc 'scarp BLOG [TAG] [TYPE] [BATCH] [CACHE_DIR]', 'Scarp a Tumblr blog'
    method_option :help, aliases: '-h', type: :boolean,
                         desc: 'Display usage information'
    def scarp(blog, tag = nil, type = nil, batch = 20, cache_dir = nil)
      if options[:help]
        invoke :help, ['scarp']
      else
        require_relative 'commands/scarp'
        TumblrScarper::Commands::Scarp.new(blog, tag, type, batch, cache_dir, options).execute
      end
    end
  end
end
