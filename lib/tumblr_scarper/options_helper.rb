require 'logging'
require 'ostruct'

module TumblrScarper
  module OptionsHelper
    DEFAULT_DL_DIR = '_tumblr_blog_images'

    def default_logging

      # Default logger
      Logging.init :debug, :verbose, :info, :happy, :warn, :success, :error, :fatal


      # here we setup a color scheme called 'bright'
      Logging.color_scheme( 'bright',
        :lines => {
          :debug    => :blue,
          :verbose  => :blue,
          :info     => :cyan,
          :happy   => :magenta,
          :warn    => :yellow,
          :success => :green,
          :error    => :red,
          :fatal    => [:white, :on_red]
        },
        :date => :gray,
        :logger => :cyan,
        :message => :magenta
      )

      Logging.appenders.stdout(
        'stdout',
        :layout => Logging.layouts.pattern(
#          :pattern => '[%d] %-5l %c: %m\n',
          :color_scheme => 'bright' #bright
        )
      )

      log = Logging.logger[TumblrScarper]
      log.appenders = Logging.appenders.stdout
      log.level = :info
      log
    end

    def default_options(log = default_logging)
      @options     = OpenStruct.new(
        :targets   => nil,
        :log       => log,
        :batch     => 20,
        :dl_root_dir       => File.join(Dir.pwd, DEFAULT_DL_DIR),
        :cache_root_dir    => nil,  # uses :dl_root_dir when nil
        :tag_on_skipped_dl => false,
        :pipeline  => {
          :scarp     => false,
          :normalize => false,
          :download  => false,
          ### TODO: tag-only step ###  :tag       => false,
        }
      )
    end

    def set_up_target_options(options, targets)
      options[:targets] = targets
      # TODO: add tags for target, based on *options* (currently only one can be used per post, and it can only be extracted automatically from the post URI)
      # TODO: add types to target, based on *options*
      options[:target_cache_dirs] = {}
      options[:target_dl_dirs] = {}
      options[:targets].each do |target|
        # TODO: sanitize all target keys + values for filesystem name
        cache_root_dir = File.join((options[:cache_root_dir] || options[:dl_root_dir]), target[:blog])
        dl_dir         = File.join(options[:dl_root_dir], target[:blog])
        cache_dir      = File.join(cache_root_dir,'.cache')
        cache_ids      = ((target.keys - [:blog]).sort.map{|k| "#{k}=#{target[k]}" })
        options[:target_cache_dirs][target] = cache_ids.empty? ? cache_dir : File.join(cache_dir, cache_ids)
        options[:target_dl_dirs][target] = dl_dir
      end
      options
    end
  end
end

