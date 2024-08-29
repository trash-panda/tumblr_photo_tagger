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
        opts.banner = "Usage:\n"
        opts.banner += "#{opts.summary_indent}Scarp API, DL, tag files:\n"
        opts.banner += "#{opts.summary_indent*2}tumblr_scarper -123 [options] BLOG|URI [...]\n\n"
        opts.banner += "#{opts.summary_indent}Retag scarped files using cached API data:\n"
        opts.banner += "#{opts.summary_indent*2}tumblr_scarper -23 [options] BLOG|URI [...]\n\n"
        opts.banner += "#{opts.summary_indent}Reformat local file metadata (using embedded MWG/Xmp-tumblr metadata):\n"
        opts.banner += "#{opts.summary_indent*2}tumblr_scarper -R [options] FILE|DIR [...]\n"

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

        opts.on('-d', '--directory PATH', "Directory to download blogs + images", "(default: '#{DEFAULT_DL_DIR}')") do |path|
          @options[:dl_root_dir] = path
        end

        opts.on('-c', '--cache-directory PATH', 'Directory to cache blog metadata', '(default: same path as --directory)') do |path|
          @options[:cache_root_dir] = path
        end

        opts.separator "\nPipeline steps:\n"
        opts.on('-1', '--[no-]scarp',     '[step 1] Scarp API data') { |v| @options[:pipeline][:scarp] = v }
        opts.on('-2', '--[no-]normalize', '[step 2] Normalize metadata') { |v| @options[:pipeline][:normalize] = v }
        opts.on('-3', '--[no-]download',  '[step 3] Download + tag images') { |v| @options[:pipeline][:download] = v }
        opts.on('-R', '--retag',  '[no steps] Sanitize metadata of local image files (not URLs)', '           based on embedded MWG/Xmp-tumblr metadata') { |v| @options[:retag] = v }

        opts.separator "\nStep-specific options:\n"
        opts.on('-a', '--[no-]cache-raw-api-results', 'Cache raw API scarper results (used for testing)') do |v|
          @options[:cache_raw_api_results] = v
        end

        opts.on('-t', '--[no-]tag-on-skipped-dl', 'Skipping a download skips the tag, too') do |v|
          @options[:tag_on_skipped_dl] = v
        end

        opts.on('-r', '--tag-rules-file FILE', "YAML file of tag rules", "(default: '#{@options.default_tag_rules_file}')") do |file|
          @options[:tag_rules_file]
        end
      end.parse!

      # If no specific steps were selected, turn on the entire pipeline
      @options.pipeline.keys.each { |k| @options.pipeline[k] = true } if @options.pipeline.values.all? { |v| v == false }
      # If retag is active, disable the rest of the pipeline
      @options.pipeline.keys.each { |k| @options.pipeline[k] = false } if @options[:retag]

      tag_rules_file = @options.tag_rules_file ||  @options.default_tag_rules_file
      @options[:tag_rules] = YAML.load_file(tag_rules_file, permitted_classes: [Regexp])
      @log.error("tag_rules are EMPTY (loaded from '#{tag_rules_file}')") if @options[:tag_rules].to_h.empty?

      @options = set_up_target_options(@options, args)
      args
    end


    def start(argv) # rubocop:disable Metrics/AbcSize
      args = parse_args(argv)
      raise("No blog targets found in args: #{args.join(', ')}") unless @options[:targets]

      @log.debug("@options: #{@options.to_h.reject { |x| %i[log target_cache_dirs target_dl_dirs].include?(x) }.to_yaml}")
      if @options[:retag]
        @log.info("Retagging downloaded images base on tag data...")
        retag_images
      else
        @log.info("Running pipeline...")
        @log.verbose("Targets to process: #{@options[:targets].join(', ')}")

        @options[:pipeline][:scarp]     ? scarp     : @log.info('---- SKIPPED SCARP API pipeline step (use -1)')
        @options[:pipeline][:normalize] ? normalize : @log.info('---- SKIPPED NORMALIZE pipeline step (use -2)')
        @options[:pipeline][:download]  ? download  : @log.info('---- SKIPPED DOWNLOAD pipeline step (user -3)')
      end

      @log.success('FINIS!')
    end

    # -----
    def retag_images
      require_relative 'retag_images'
      paths = @options.targets.empty? ? [ @options.dl_root_dir ] : @options.targets
      @retagger = TumblrScarper::RetagImages.new @options
      @retagger.retag_paths(paths)
    end

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
