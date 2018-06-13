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

    desc 'scarp BLOG [TAG] [TYPE] [BATCH] [CACHE-DIR]', 'Scarp a Tumblr blog'
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
