# frozen_string_literal: true

require 'logging'
require 'ostruct'

# rubocop:disable Metrics/MethodLength, Metrics/AbcSize
module TumblrScarper
  # Data structure with @options; sets up default logging and default options
  module OptionsHelper
    DEFAULT_DL_DIR = '_tumblr_blog_images'

    def default_logging
      # Default logger
      Logging.init :debug2, :debug, :verbose, :info, :happy, :warn, :success, :todo, :error, :recovery, :fatal

      # here we setup a color scheme called 'bright'
      Logging.color_scheme(
        'bright',
        lines: {
          debug2: %i[dark blue on_black],
          debug: :blue,
          verbose: :blue,
          info: :cyan,
          happy: :bright_magenta,
          warn: :yellow,
          success: :green,
          todo: %i[black on_yellow],
          recovery: %i[black on_green],
          error: :red,
          fatal: %i[white on_red]
        },
        date: :gray,
        logger: :cyan,
        message: :magenta
      )

      Logging.appenders.stdout(
        'stdout',
        layout: Logging.layouts.pattern(
          #          :pattern => '[%d] %-5l %c: %m\n',
          color_scheme: 'bright' # bright
        )
      )

      log = Logging.logger[TumblrScarper]
      log.add_appenders(
        Logging.appenders.stdout(
          layout: Logging.layouts.pattern(color_scheme: 'bright')
        ),
        Logging.appenders.rolling_file(
          "tumblr_scarper.debug.log",
                keep: 3,
          level: :debug,
          layout: Logging.layouts.pattern(backtrace: true),
          truncate: true
        ),
      )
      log.level = :info
      log
    end

    def default_options(log = default_logging)
      @options = OpenStruct.new(
        targets: nil,
        batch_size: 20,
        dl_root_dir: File.join(Dir.pwd, DEFAULT_DL_DIR),
        cache_root_dir: nil, # uses :dl_root_dir when nil
        tag_on_skipped_dl: false,
        cache_raw_api_results: false,
        retag: false,
        default_tag_rules_file: File.expand_path( 'data/default_tag_rules.yaml', __dir__ ),
        pipeline: {
          scarp: false,
          normalize: false,
          download: false
          ### TODO: tag-only step ###  :tag       => false,
        },
        log: log
      )
    end

    # Returns :blog from arg, which can be a blog name or tumblr post uri
    def blog_data_from_arg(arg) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
      data = {}
      arg = arg.gsub(/\?.*\Z/,'') # remove nuisance args from URL (like ?source=share)
      case arg
      when %r{^(https?://)?www\.tumblr\.[a-z]+}
        uri_parts = arg.sub(%r{^https?://}, '').split('/')
        if uri_parts[1,2] == %w[liked by]
          data[:likes] = uri_parts[3]
        elsif uri_parts[2] == 'likes'
          data[:likes] = uri_parts[1]  
        else
          data[:blog] = uri_parts[1]
          data[:id] = uri_parts[2] if uri_parts[2] =~ /\A\d+\Z/
          data[:tag] = uri_parts[3] if uri_parts[2] == 'tagged'
        end
      when %r{^(https?://)?[a-z0-9_-]+\.tumblr.[a-z]+}
        uri_parts = arg.sub(%r{^https?://}, '').split('/')
        uri_parts.delete_at(1) if uri_parts[1] == 'archive'
        data[:id] = uri_parts[2] if uri_parts[1] == 'post'
        data[:tag] = uri_parts[2] if uri_parts[1] == 'tagged'
        data[:blog] = uri_parts.first.split('.').first
      when /^[a-z0-9_-]+$/
        data[:blog] = arg
      when %r{^https?://([a-z0-9_.-]+)/}
        data[:blog] = Regexp.last_match(1)
        uri_parts = arg.sub(%r{^https?://}, '').split('/')
        data[:id] = uri_parts[2] if uri_parts[1] == 'post'
        data[:tag] = uri_parts[2] if uri_parts[1] == 'tagged'
      else
        @log.fatal "Cannot determine blog name from '#{arg}'!"
      end



      require 'cgi'
      data[:tag] = CGI.unescape(data[:tag]) if data[:tag]
      @log.info "data:\n#{data.to_yaml}"

      data
    end

    def set_up_retag_target_options(options,args)
      options[:targets] = args.map do |path|
        path = path.gsub(/\?.*\Z/,'')
        if path =~ /\Ahttps?/
          data = blog_data_from_arg(path)
          @log.error("IF you are here, you are probably trying to locate and retag a local image file from a URL argument.  What is the best way to find if the file is downloaded?  If we only derive from the url strings, it might be wrong.  If we look it up from the cache, it requires the cache to be there.  Time to think and decide; I punted because it wasn't that important and it was almost midnight.")
          require 'pry'; binding.pry
        end
        path
      end.map do |path|
        unless File.exist?(path)
          msg = "No file or directory at #{path}"
          @log.error(msg)
          #fail Errno::ENOENT, msg
          next nil
        end
        path
      end
      options
    end

    def set_up_target_options(options,args)
      options = options.dup

      if options.retag
        return set_up_retag_target_options(options,args)
      end
      
      targets = args.map { |arg| blog_data_from_arg(arg) }
      options[:targets] = targets

      # TODO: add tags for target, based on *options*
      #  (currently only one can be used per post, and it can only be extracted
      #    automatically from the post URI)
      # TODO: add types to target, based on *options*
      options[:target_cache_dirs] = {}
      options[:target_dl_dirs] = {}
      options[:targets].each do |target|
        # TODO: sanitize all target keys + values for filesystem name
        cache_root_dir = File.join((
          options[:cache_root_dir] || options[:dl_root_dir]), 
          target[:likes] ? "#{target[:likes]}/likes" : target[:blog]
        )
        dl_dir         = File.join(
          options[:dl_root_dir],
          target[:likes] ? "#{target[:likes]}/likes" : target[:blog]
        )
        cache_dir      = File.join(cache_root_dir, '.cache')
        cache_ids      = ((target.keys - [:blog]).sort.map { |k| "#{k}=#{target[k]}" })
        options[:target_cache_dirs][target] = cache_ids.empty? ? cache_dir : File.join(cache_dir, cache_ids)
        options[:target_dl_dirs][target] = dl_dir
      end
      options
    end
    
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize
