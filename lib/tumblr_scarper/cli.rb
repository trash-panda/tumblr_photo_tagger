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
    method_option :ban_posts_tagged, aliases: '-D', type: :string,
                         desc: 'Skip posts with any of these comma-delimited tags'
    method_option :accept_posts_tagged, aliases: '-A', type: :string,
                         desc: 'Only include posts with these comma-delimited tags'
    method_option :delete_tags, aliases: '-d', type: :string,
                         desc: 'Comma-delimited list of tags to remove from normalized tag list'
    method_option :accept_tags, aliases: '-a', type: :string,
                         desc: 'Comma-delimited list of image tags to include in normalized tag list'
    method_option :lowercase_tags, aliases: '-l', type: :boolean,
                         desc: 'transforms all image tags to lower case'
    method_option :skip_untagged, aliases: '-s', type: :boolean,
                         desc: 'skip images without tags'
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
