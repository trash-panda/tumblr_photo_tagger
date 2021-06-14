# frozen_string_literal: true

require 'optparse'
require 'yaml'
require 'tumblr_scarper/options_helper'

module TumblrScarper
  # Handle the application command line parsing
  # and the dispatch to various command objects
  #
  # @api public
  class CLI # rubocop:disable Metrics/ClassLength
    include TumblrScarper::OptionsHelper

    # Error raised by this runner
    Error = Class.new(StandardError)

    def version
      require_relative 'version'
      puts "v#{TumblrScarper::VERSION}"
    end

    def initialize
      @options = default_options
      @log = @options[:log]
      @log.info "#{self.class} init"
    end

    def parse_args(_argv) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      args = OptionParser.new do |opts|
        opts.banner = "Usage:\n\n#{opts.summary_indent}tumblr_scarper [options] BLOG|URI [...]"

        # tag
        # type
        # batch
        # cache_dir

        opts.separator "\nGlobal options:\n"
        opts.on('-v', '--[no-]verbose', 'Run verbosely (additive)') do |v|
          incr = ((v ? -1 : 1) * 1)
          @options[:log].level += incr unless (@options[:log].level + incr).negative?
          @log.info("Log level + #{incr}")
          @log.info(Logging.show_configuration)
        end

        opts.on('-d', '--directory PATH', "Directory to download blogs + images (default: '#{DEFAULT_DL_DIR}')") do |path|
          @options[:dl_root_dir] = path
        end

        opts.on('-c', '--cache-directory PATH', 'Directory to cache blog metadata (default: same path as --directory)') do |path|
          @options[:cache_root_dir] = path
        end

        opts.separator "\nPipeline steps:\n"
        opts.on('-1', '--[no-]scarp',     '[step 1] Scarp API data') { |v| @options[:pipeline][:scarp] = v }
        opts.on('-2', '--[no-]normalize', '[step 2] Normalize metadata') { |v| @options[:pipeline][:normalize] = v }
        opts.on('-3', '--[no-]download',  '[step 3] Download + tag images') { |v| @options[:pipeline][:download] = v }

        opts.separator "\nStep-specific options:\n"
        opts.on('-a', '--[no-]cache-raw-api-results', 'Cache raw API scarper results (used for testing)') do |v|
          @options[:cache_raw_api_results] = v
        end

        opts.on('-t', '--[no-]tag-on-skipped-dl', 'Skipping a download skips the tag, too') do |v|
          @options[:tag_on_skipped_dl] = v
        end
      end.parse!

      # If no specific steps were selected, turn on the entire pipeline
      @options.pipeline.keys.each { |k| @options.pipeline[k] = true } if @options.pipeline.values.all? { |v| v == false }

      targets = args.map { |arg| blog_data_from_arg(arg) }
      @options = set_up_target_options(@options, targets)
      args
    end

    # Returns :blog frm arg, which can be a blog name or tumblr post uri
    def blog_data_from_arg(arg) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
      data = {}
      case arg
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

    def start(argv) # rubocop:disable Metrics/AbcSize
      args = parse_args(argv)
      raise("No blog targets found in args: #{args.join(', ')}") unless @options[:targets]

      @log.debug("@options: #{@options.to_h.reject { |x| %i[log target_cache_dirs target_dl_dirs].include?(x) }.to_yaml}")
      @log.verbose("Targets to process: #{@options[:targets].join(', ')}")

      @options[:pipeline][:scarp]     ? scarp     : @log.info('---- SKIPPED SCARP pipeline step (use -1)')
      @options[:pipeline][:normalize] ? normalize : @log.info('---- SKIPPED NORMALIZE pipeline step (use -2)')
      @options[:pipeline][:download]  ? download  : @log.info('---- SKIPPED DOWNLOAD pipeline step (user -3)')

      @log.success('FINIS!')
    end

    # -----

    def scarp
      require_relative 'scarper'
      scarper = TumblrScarper::Scarper.new @options
      @options.targets.each do |target|
        @log.info("\n\n==== TUMBLR SCARP: #{target}\n\n")
        scarper.scarp(target)
      end
    end

    def normalize
      require_relative 'normalizer'
      normalizer = TumblrScarper::Normalizer.new @options
      @options.targets.each do |target|
        @log.info("\n\n==== TUMBLR NORMALIZE: #{target}\n\n")
        normalizer.normalize(target)
      end
    end

    def download
      require_relative 'downloader'
      downloader = TumblrScarper::Downloader.new @options
      @options.targets.each do |target|
        @log.info("\n\n==== TUMBLR DOWNLOAD: #{target}\n\n")
        downloader.download(target)
      end
    end
  end
end
