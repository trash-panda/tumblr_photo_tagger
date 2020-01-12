require 'optparse'
require 'ostruct'

module TumblrScarper
  # Handle the application command line parsing
  # and the dispatch to various command objects
  #
  # @api public
  class NewCLI
    # Error raised by this runner
    Error = Class.new(StandardError)

    def version
      require_relative 'version'
      puts "v#{TumblrScarper::VERSION}"
    end

    def initialize
      require 'logging'

      # Default logger
      #

      # here we setup a color scheme called 'bright'
      Logging.color_scheme( 'bright',
        :levels => {
          :info  => :green,
          :warn  => :yellow,
          :error => :red,
          :fatal => [:white, :on_red]
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

      @log = Logging.logger[TumblrScarper]

      @log.appenders = Logging.appenders.stdout
      @log.level = :warn
      @log.warn  "#{self.class} init"

      @options     = OpenStruct.new(
        :targets   => nil,
        :log       => @log,
        :batch     => 20,
        :cache_dir => Dir.pwd,
      )
    end

    def parse_args(argv)
      args = OptionParser.new do |opts|
        opts.banner = "Usage: tumblr_scarper [options] BLOG|POST ..."
        # tag
        # type
        # batch
        # cache_dir

        opts.on("-v", "--[no-]verbose", "Run verbosely (additive)") do |v|
          incr = ((v ? -1 : 1) * 1)
          @options[:log].level += incr unless( (@options[:log].level + incr) < 0 )
          @log.info( "Log level + #{incr}")
          @log.info( Logging.show_configuration )
        end
      end.parse!

      @options[:targets] = args.map{|arg| blog_data_from_arg(arg) }
      args
    end

    # Returns :blog frm arg, which can be a blog name or tumblr post uri
    def blog_data_from_arg(arg)
      data = {}
      if arg =~ %r{^(https?://)?[a-z0-9_-]+\.tumblr.[a-z]+}
        uri_parts = arg.sub(%r{^https?://},'').split('/')
        data[:id] = uri_parts[2] if uri_parts[1] == 'post'
        data[:tag] = uri_parts[2] if uri_parts[1] == 'tagged'
        data[:blog] = uri_parts.first.split('.').first
      elsif arg =~ /^[a-z0-9_-]+$/
        data[:blog] = arg
      end
      data
    end


    def start(argv)
      args = parse_args(argv)

      fail("No blog targets found in args: #{args.join(', ')}") unless @options[:targets]
      require 'yaml'
      @log.debug("@options: #{@options.to_h.reject{|x| x == :log }.to_yaml}")
      @log.warn("Targets to process: #{@options[:targets].join(", ")}")
      require_relative 'scarper'
      require_relative 'normalizer'
      require_relative 'downloader'

      @options.targets.each do |target|
        # TODO: sanitize all keys + values for filesystem name
				cache_ids = ((target.keys - [:blog]).sort.map{|k| "#{k}=#{target[k]}" })
        dl_dir = File.join(@options.cache_dir, target[:blog])
        cache_dir = dl_dir
        cache_dir = cache_ids.empty? ? cache_dir : File.join(cache_dir, cache_ids)
				# TODO: add tags to target, based on options
				# TODO: add types to target, based on options

				@scarper = TumblrScarper::Scarper.new cache_dir
				path = @scarper.scarp(target, @options)
      end
      require 'pry'; binding.pry
    end


  end
end