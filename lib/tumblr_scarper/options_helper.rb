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
  end
end

