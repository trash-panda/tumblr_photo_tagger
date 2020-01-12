require 'optparse'
require 'ostruct'
require 'yaml'

module TumblrScarper
  # Handle the application command line parsing
  # and the dispatch to various command objects
  #
  # @api public
  class CLI
    # Error raised by this runner
    Error = Class.new(StandardError)

    def version
      require_relative 'version'
      puts "v#{TumblrScarper::VERSION}"
    end

    def initialize
      require 'logging'

      # Default logger
      Logging.init :debug, :info, :happy, :warn, :success, :error, :fatal


      # here we setup a color scheme called 'bright'
      Logging.color_scheme( 'bright',
        :levels => {
          :info  => :cyan,
          :happy => :green,
          :warn  => :yellow,
          :success => [:blue],
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
      @log.level = :info
      @log.warn  "#{self.class} init"

      @options     = OpenStruct.new(
        :targets   => nil,
        :log       => @log,
        :batch     => 20,
        :cache_root_dir => File.join(Dir.pwd,'tumblr_blogs'),
        :pipeline  => {
          :scarp     => false,
          :normalize => false,
          :download  => false,
          ### TODO: tag-only step ###  :tag       => false,
        }
      )
    end

    def parse_args(argv)
      args = OptionParser.new do |opts|
        opts.banner = "Usage:\n\n#{opts.summary_indent}tumblr_scarper [options] BLOG|URI [...]"

        # tag
        # type
        # batch
        # cache_dir

        opts.separator "\nGlobal options:\n"
        opts.on("-v", "--[no-]verbose", "Run verbosely (additive)") do |v|
          incr = ((v ? -1 : 1) * 1)
          @options[:log].level += incr unless( (@options[:log].level + incr) < 0 )
          @log.info( "Log level + #{incr}")
          @log.info( Logging.show_configuration )
        end

        opts.separator "\nPipeline steps:\n"
        opts.on('-1', '-s', '--[no-]scarp',  '[step 1] Scarp API data') { |v| @options[:pipeline][:scarp] = v }
        opts.on('-2', '-n', '--[no-]normalize',  '[step 2] Normalize metadata') { |v| @options[:pipeline][:normalize] = v }
        opts.on('-3', '-d', '--[no-]download',  '[step 3] Download + tag images') { |v| @options[:pipeline][:download] = v }
      end.parse!

      # If no specific steps were selected, turn on the entire pipeline
      if @options.pipeline.values.all?{|v| v == false}
        @options.pipeline.keys.each{|k| @options.pipeline[k] = true }
      end

      @options[:targets] = args.map{|arg| blog_data_from_arg(arg) }
      # TODO: add tags to target, based on *options*
      # TODO: add types to target, based on *options*
      @options[:target_cache_dirs] = {}
      @options[:target_dl_dirs] = {}
      @options.targets.each do |target|
        # TODO: sanitize all target keys + values for filesystem name
        blog_root_dir = File.join(@options.cache_root_dir, target[:blog])
        dl_dir        = File.join(blog_root_dir)
        cache_dir     = File.join(blog_root_dir,'.cache')

        cache_ids     = ((target.keys - [:blog]).sort.map{|k| "#{k}=#{target[k]}" })
        @options[:target_cache_dirs][target] = cache_ids.empty? ? cache_dir : File.join(cache_dir, cache_ids)
        @options[:target_dl_dirs][target] = dl_dir
      end
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
      @log.debug("@options: #{@options.to_h.reject{|x| [:log,:target_cache_dirs,:target_dl_dirs].include?(x) }.to_yaml}")
      @log.warn("Targets to process: #{@options[:targets].join(", ")}")

      @options[:pipeline][:scarp]     ? scarp     : @log.info('---- SKIPPED SCARP pipeline step (use -1)')
      @options[:pipeline][:normalize] ? normalize : @log.info('---- SKIPPED NORMALIZE pipeline step (use -2)')
      @options[:pipeline][:download]  ? download  : @log.info('---- SKIPPED DOWNLOAD pipeline step (user -3)')

      @log.happy('FINIS!')
    end

    def scarp
      require_relative 'scarper'
      scarper = TumblrScarper::Scarper.new @options
      @options.targets.each do |target|
        @log.info( "\n\n==== TUMBLR SCARP: #{target}\n\n" )
        path = scarper.scarp(target)
      end
    end

    def normalize
      require_relative 'normalizer'
      normalizer = TumblrScarper::Normalizer.new @options
      @options.targets.each do |target|
        @log.info( "\n\n==== TUMBLR NORMALIZE: #{target}\n\n" )
        path = normalizer.normalize(target)
      end
    end

    def download
      require_relative 'downloader'
      downloader = TumblrScarper::Downloader.new @options
      @options.targets.each do |target|
        @log.info( "\n\n==== TUMBLR DOWNLOAD: #{target}\n\n" )
        path = downloader.download(target)
      end
    end

  end
end
