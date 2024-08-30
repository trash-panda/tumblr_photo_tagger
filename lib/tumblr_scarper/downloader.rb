require 'yaml'

require 'multi_exiftool'
require 'fileutils'
require 'date'
require 'tumblr_scarper/content_helpers'
require 'tumblr_scarper/tag_normalizer'

module TumblrScarper
  class Downloader
    include FileUtils::Verbose
    def initialize(options)
      @writer_errors = {
        corrected: [],
        failed: [],
      }
      @options = options
      @log = options.log
      @tag_rules = options.tag_rules
      @tag_normalizer = TumblrScarper::TagNormalizer.new(tag_rules: @tag_rules, log: @log)
    end

    def normalized_photo_metadata cache_path
      YAML.load_file File.join(cache_path, 'url-tags-downloads.yaml')
    end

    def download_to_file(url, file_path)
      # ----------------------------------------
      # Download image to File
      # ----------------------------------------
      file_path_renamedjpg = file_path.sub(/\.(png|gif)$/, "--\\1.jpg")

      unless File.exist?(file_path) || File.exist?(file_path_renamedjpg)
        downloaded_file = download_url_to_tmpfile(url)
        unless File.exist?(downloaded_file)
          @log.todo "Somehow the downloaded file doesn't exist.  Investigate why:"
          require 'pry'; binding.pry
          return false
        end

        require 'pry'; binding.pry if (downloaded_file.path =~ /dutifullyfriedharmony-berührungspunkte/)
        require 'pry'; binding.pry if (file_path =~ /dutifullyfriedharmony-berührungspunkte/)
        cp downloaded_file, file_path
        @log.success "Downloaded '#{url}' to '#{file_path}'"
        true
      else
        if File.exist?(file_path)
          @log.happy "SKIP: skipping download - File exists: '#{file_path}'"
        else
          @log.happy "SKIP: skipping download - File exists: '#{file_path_renamedjpg}'"
        end
        false
      end
    end

      # ----------------------------------------
      # Prepare Tag Data for exiftool
      # ----------------------------------------
      #
      # ## Metadata conventions:
      #
      # ### Simple conventions:
      #
      #   URL of resource/image (http://foo.bar/images/image.jpg)
      #     * xmp-dc:identifier     [dlf-1], [dlf-2] (as unique identifier)
      #     * xmp-dc:source         [exif-url]
      #     * xmp-photoshop:source  (displayed by DigiKam)
      #
      #   xmp-dc:relation   = list of URLs of context pages (http://foor.bar/blog/123/)
      #
      # Based on best-effort implementation of:
      #   * The Digital Library Foundation's "Best Practices for Shareable Metadata" [dlf-0]
      #   * "Adding the source URL to an image's meta data" [exif-url]
      #
      # [exif-url]: https://cweiske.de/tagebuch/exif-url.htm
      # [dlf-0]:    http://webservices.itcs.umich.edu/mediawiki/oaibp/index.php/ShareableMetadataPublic
      # [dlf-1]:    http://webservices.itcs.umich.edu/mediawiki/oaibp/index.php/IdentifyingTheResource#Identifying_the_Resource
      # [dlf-2]:    http://webservices.itcs.umich.edu/mediawiki/oaibp/index.php/AppropriateLinks
      #
      # ### MWG conventions
      #
      # xmp-mwg-coll:Collections
    def prepare_tag_data(url, post)
      post_datetime = DateTime.parse(post[:date_gmt])
      if post[:caption].nil?
        @log.todo "Somehow `post[:caption]` is nil; investigate why!"
        require 'pry'; binding.pry
      end

      caption = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post[:caption])

      unless post[:tags].empty?
        caption =  TumblrScarper::ContentHelpers.to_exiftool_newlines(
          TumblrScarper::ContentHelpers.taglined_caption(tags: post[:tags], caption: caption)
        )
      end

      @log.verbose caption.gsub('&#xd;&#xa;', "\n")
      new_mwg_kewords = @tag_normalizer.normalize(post[:tags])

      writer_values = {
        'MWG:description'          => caption, # sets 'exif:imagedescription'
        'xmp-dc:identifier'        => url,                                  # [dlf-1], [dlf-2]
        'xmp-dc:source'            => url,                                  # [exif-url]
        'xmp-dc:relation'          => [post[:url], post[:image_permalink]], # [dlf-1]
        'xmp-photoshop:source'     => url,                                  # displayed by DigiKam
        'xmp-photoshop:credit'     => post[:url],                           # displayed by DigiKam
        'MWG:Keywords'             => new_mwg_kewords,
        'xmp-mwg-coll:Collections' => [],
        'MWG:CreateDate'           => post_datetime,
        'XMP-tumblr:TumblrTags'    => post[:tags],
        #'iptc:codedcharacterset'   => 'utf8',
        #'xmp:createdate'             => post_datetime,
      }

      writer_values['xmp-dc:title'] = post[:title] if post[:title]

      if post[:source_url]
        writer_values['xmp-dc:relation'] = [post[:source_url]] + writer_values['xmp-dc:relation']
        writer_values['xmp-mwg-coll:Collections'] << %Q({CollectionName=Tumblr Source Post,CollectionURI=#{post[:source_url].gsub(',', '%2C')}})
      end

      if post[:link_url]
        # NOTE: This hack sanitizes urls that uuencode special characters
        #       EXCEPT for commas (a violation of RFC3986, section 2.3)
        # TODO: is there a better way to handle this?
        link_url = post[:link_url].gsub(',', '%2C')
        writer_values['xmp-dc:relation'] = [link_url] + writer_values['xmp-dc:relation']
        writer_values['xmp-mwg-coll:Collections'] << "{CollectionName=Original Link,CollectionURI=#{link_url}}"
        writer_values['CreatorWorkURL'] = link_url
      end

      writer_values['xmp-mwg-coll:Collections'] << "{CollectionName=Tumblr Post,CollectionURI=#{post[:url]}}"

      if post[:image_permalink]
        writer_values['xmp-mwg-coll:Collections'] << "{CollectionName=Tumblr Image Permalink,CollectionURI=#{post[:image_permalink]}}"
      end

      writer_values
    end

    def configured_exiftool_writer(file_path, url, post)
      writer = MultiExiftool::Writer.new
      writer.filenames = file_path
      writer.config = File.join(__dir__,'files','.ExifTool_config')
      writer.options = { 'P' => true, 'E' => true }
      writer.overwrite_original = true
      writer.values = prepare_tag_data(url, post)
      writer
    end

    def workaround_png_looks_like_jpeg_error(writer, result)
      # WARNING: this will mean a subsequent dl will alway  dl the png again
      # TODO: record errors (see @writer_errors)
      if writer.errors.any? { |e| e =~ /Error: Not a valid ([A-Z]+) \(looks more like a JPEG\) - (.*)/ }
        ext         = Regexp.last_match(1).downcase
        broken_file = Regexp.last_match(2)
        new_file    = broken_file.sub(/\.#{ext}$/i, "--#{ext}.jpg")
        mv broken_file, new_file
        @log.recovery "    !!! RENAMED '#{broken_file}' to '#{new_file}'"

        # NOTE: write.filenames will always be a single file, so the "other_files" shouldn't be needed
        other_files = writer.filenames - [broken_file]
        writer.filenames = [new_file] + other_files
        result = writer.write
      elsif writer.errors.any?{|x| x =~ /\AError: File not found.*\.png\Z/ }
        writer.filenames
        writer.filenames.map!{|x| x.sub(/\.png$/,'--png.jpg')}
        result = writer.write
      end
      result
    end

    def workaround_looks_like_png_error(writer, result)
      # WARNING: this will mean a subsequent dl will alway  dl the png again
      # TODO: record errors (see @writer_errors)
      if writer.errors.any? { |e| e =~ /Error: Not a valid ([A-Z]+) \(looks more like a PNG\) - (.*)/ }
        ext         = Regexp.last_match(1).downcase
        broken_file = Regexp.last_match(2)
        new_file    = broken_file.sub(/\.#{ext}$/i, "--#{ext}.png")
        mv broken_file, new_file
        @log.recovery "    !!! RENAMED '#{broken_file}' to '#{new_file}'"

        # NOTE: write.filenames will always be a single file, so the "other_files" shouldn't be needed
        other_files = writer.filenames - [broken_file]
        writer.filenames = [new_file] + other_files
        result = writer.write
      elsif writer.errors.any?{|x| x =~ /\AError: File not found.*\.jpe?g\Z/ }
        writer.filenames
        writer.filenames.map!{|x| x.sub(/\.(jpe?g|gif|webm)$/,'--\\1.jpg')}
        result = writer.write
      end
      result
    end


    def workaround_cant_read_exififd_data_error(writer, file_path, result)
      if writer.errors.any? { |e| e =~ /Can.{0,5}t read ExifIFD data/ }
        # Verify type of file, too
        # For
        #   Bad ExifOffset SubDirectory start
        #   http://owl.phy.queensu.ca/~phil/exiftool/faq.html#Q20
        #   exiftool -all= -tagsfromfile @ -all:all -unsafe -icc_profile bad.jpg
        cmd = "exiftool -all= -tagsfromfile @ -all:all -unsafe -icc_profile '#{file_path}'"
        @log.error "TAG:  == Trying to fix by running `#{cmd}` first"
        @log.error `#{cmd}`
        if $?.success?
          @log.recovery 'TAG:  ++ removed broken existing metadata!'
          @log.recovery 'TAG:  ++ rewriting metadata'
          result = writer.write
          sleep 5 if result
          result
        end
      end
      result
    end

    # ----------------------------------------
    # Write Tag to File
    # ----------------------------------------
    def write_tag_to_file(file_path, url, post, photos)
      writer = configured_exiftool_writer(file_path, url, post)

      result = writer.write
      touch file_path, mtime: DateTime.parse(post[:date_gmt]).to_time # Change file mtime to post time

      unless result || writer.errors.first =~ /\d image files updated$/
        @log.error "TAG: Tagging failed: '#{writer.errors}'"

        result = workaround_png_looks_like_jpeg_error(writer, result)
        result = workaround_looks_like_png_error(writer, result)
        result = workaround_cant_read_exififd_data_error(writer, file_path, result)
        
        unless result
          @log.error "TAG: Tagging uncorrectably failed: '#{writer.errors}'\n\n\tfile: '#{file_path}'\n\tpost: '#{post[:url]}'\n\turl:  '#{url}'"
          if writer.errors.first =~ /^Warning: \[Minor\]/i # rubocop:disable Style/Semicolon, Lint/Debugger
            @log.verbose('  TAG: Continuing because this is a minor error')
          elsif writer.errors.first =~ /Warning: Some character\(s\) could not be encoded in Latin/
            @log.verbose("  TAG: Continuing because AFAICT, the characters are usually emoji and usually still work in captions")
          else
            @log.todo("This error isn't handled.  If pry is installed, investigate it")
            require 'pry'; binding.pry
          end
        end
      end

      @log.success "TAG: Tagged metadata for '#{file_path}'" if result
    end

    # Download + Tag images
    def download(target)
      cache_dir = @options[:target_cache_dirs][target]
      dl_dir    = @options[:target_dl_dirs][target]
      photos = normalized_photo_metadata(cache_dir) # load photo metadata
      mkdir_p dl_dir

      n = 0
      photos.each do |url, post|
        n += 1
        file_path = File.join(dl_dir, "#{post[:local_filename]}#{File.extname(url)}")

        @log.info ''
        @log.info "DOWNLOAD [#{n.to_s.rjust(photos.size.to_s.size)}/#{photos.size}] #{url}"
        @log.verbose "#{post.to_yaml}\n----\n"

        # TODO TODO: make metadata its own object
        # TODO TODO TODO: dl+metadata at same time OR metadata as a separate step
        unless download_to_file(url, file_path)
          unless @options[:tag_on_skipped_dl]
            @log.happy 'SKIP: skipping metadata, too!'
            next
          end
        end

        @log.info "TAG [#{n.to_s.rjust(photos.size.to_s.size)}/#{photos.size}] #{file_path}"
        write_tag_to_file(file_path, url, post, photos)
      end
      dl_dir
    end

    private

    ##------------
    ## A safe way in Ruby to download a file to disk using open-uri
    ## From: https://gist.github.com/janko/7cd94b8b4dd113c2c193
    ##------------
    require 'open-uri'
    require 'net/http'

    Error = Class.new(StandardError)

    DOWNLOAD_ERRORS = [
      SocketError,
      OpenURI::HTTPError,
      RuntimeError,
      URI::InvalidURIError,
      Error
    ].freeze

    # Downloads URL to tmp file; returns path to tmp file
    def download_url_to_tmpfile(url, max_size: nil)
      require 'cgi'
      url = URI::DEFAULT_PARSER.escape(URI::DEFAULT_PARSER.unescape(url))
      url = URI(url)
      raise Error, 'url was invalid' unless url.respond_to?(:open)

      options = {}
      options['User-Agent'] = 'MyApp/1.2.3'
      options[:content_length_proc] = ->(size) {
        raise Error, "file is too big (max is #{max_size})" if max_size && size && size > max_size
      }

      # open-uri will return a StringIO instead of a Tempfile if the filesize
      # is less than 10 KB, so we patch this behaviour by converting it into a
      # Tempfile.
      downloaded_file = url.open(options)
      if downloaded_file.is_a?(StringIO)
        tempfile = Tempfile.new('open-uri', binmode: true)
        IO.copy_stream(downloaded_file, tempfile.path)
        downloaded_file = tempfile
      end

      downloaded_file
    rescue *DOWNLOAD_ERRORS => e
      raise if e.instance_of?(RuntimeError) && e.message !~ /redirection/

      raise Error, "download failed (#{url}): #{e.message}"
    end
  end
end
