require 'yaml'

require 'multi_exiftool'
require 'fileutils'
require 'date'
require 'tumblr_scarper/content_helpers'

include  FileUtils::Verbose
module TumblrScarper
  class Downloader
    include  FileUtils::Verbose
    def initialize(options)
      @writer_errors = {
        corrected: [],
        failed: [],
      }
      @options = options
      @log = options.log
    end

    def normalized_photo_metadata  cache_path
      YAML.load_file File.join(cache_path,"url-tags-downloads.yaml")
    end

    def download(target)
      cache_dir = @options[:target_cache_dirs][target]
      dl_dir    = @options[:target_dl_dirs][target]
      mkdir_p dl_dir

      photos = normalized_photo_metadata(cache_dir) # load photo metadata

      n = 0
      photos.each do |url,post|
        n+=1
        @log.info ''
        @log.info "DOWNLOAD [#{n.to_s.rjust(photos.size.to_s.size)}/#{photos.size}] #{url}"
        @log.verbose "#{post.to_yaml}\n----\n"

        file = "#{post[:local_filename]}#{File.extname(url)}"
        file_path = File.join( dl_dir, file )
        file_path_renamedjpg = file_path.sub(/\.(png|gif)$/, "--\\1.jpg")
        unless File.exists?(file_path) || File.exist?(file_path_renamedjpg)
          downloaded_file = _download url
          cp downloaded_file, file_path
          @log.success "Downloaded '#{url}' to '#{file_path}'"
        else
          if File.exists?(file_path)
            @log.happy "SKIP: skipping download - File exists: '#{file_path}'"
          else
            @log.happy "SKIP: skipping download - File exists: '#{file_path_renamedjpg}'"
          end
          # TODO TODO: make metadata its own object
          # TODO TODO TODO: dl+metadata at same time OR metadata as a separate step
          unless @options[:tag_on_skipped_dl]
            @log.happy "SKIP: skipping metadata, too!"
            next
          end
        end

        @log.info "TAG [#{n.to_s.rjust(photos.size.to_s.size)}/#{photos.size}] #{file_path}"
        post_datetime = DateTime.parse(post[:date_gmt])
        caption  = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post[:caption])

        writer = MultiExiftool::Writer.new
        writer.filenames = file_path
        writer.options = { 'P' => true, 'E' => true }
        writer.overwrite_original = true

        writer_values = {
          #'exif:imagedescription'      => caption,
          'MWG:description'            => caption,
          'xmp-dc:identifier'          => url,                                  # [dlf-1], [dlf-2]
          'xmp-dc:source'              => url,                                  # [exif-url]
          'xmp-dc:relation'            => [post[:url],post[:image_permalink]],  # [dlf-1]
          'xmp-photoshop:source'       => url,                                  # displayed by DigiKam
          'xmp-photoshop:credit'       => post[:url],                           # displayed by DigiKam
          #'xmp:subject'                => post[:tags],
          'MWG:Keywords'               => post[:tags],
          'xmp-mwg-coll:Collections'   => [],
          'MWG:CreateDate'             => post_datetime,
          #'xmp:createdate'             => post_datetime,
        }

        writer_values['xmp-dc:title'] = post[:title] if post[:title]

        if post[:source_url]
          writer_values['xmp-dc:relation'] = [post[:source_url]] + writer_values['xmp-dc:relation']
          writer_values['xmp-mwg-coll:Collections'] = [%Q[{CollectionName=Tumblr Source Post,CollectionURI=#{post[:source_url]}}]] + writer_values['xmp-mwg-coll:Collections']
        end

        if post[:link_url]
          # NOTE: This hack fixes urls that uuencode special character EXCEPT for commas (violating RFC3986, section 2.3)
          # TODO: is there a better way to handle this?
          link_url = post[:link_url].gsub(',','%2C')
          writer_values['xmp-dc:relation'] = [link_url] + writer_values['xmp-dc:relation']
          writer_values['xmp-mwg-coll:Collections'] = [%Q[{CollectionName=Original Link,CollectionURI=#{link_url}}]] + writer_values['xmp-mwg-coll:Collections']
          writer_values['CreatorWorkURL'] = link_url
        end

        writer_values['xmp-mwg-coll:Collections'] << %Q[{CollectionName=Tumblr Post,CollectionURI=#{post[:url]}}]

        if post[:image_permalink]
          writer_values['xmp-mwg-coll:Collections'] << %Q[{CollectionName=Tumblr Image Permalink,CollectionURI=#{post[:image_permalink]}}]
        end


        writer.values = writer_values.dup
        # Metadata conventions:
        #
        #   URL of resource     (http://foo.bar/images/image.jpg)
        #     * xmp-dc:identifier     [dlf-1], [dlf-2] (as unique identifier)
        #     * xmp-dc:source         [exif-url]
        #     * xmp-photoshop:source  displayed by DigiKam
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
        result = writer.write
        touch file_path, mtime: Time.parse(post_datetime.to_s)

        @log.verbose caption.gsub('&#xd;&#xa;',"\n")

        unless result || writer.errors.first =~ /\d image files updated$/
          @log.error "TAG: Tagging failed: '#{writer.errors}'"

          # WARNING: this will mean a subsequent dl will alway  dl the png again
          # TODO: record errors (see @writer_errors)
          if writer.errors.any?{|e| e =~ /Error: Not a valid ([A-Z]+) \(looks more like a JPEG\) - (.*)/}
             ext         = $1.downcase
             broken_file = $2
             new_file    = broken_file.sub(/\.#{ext}$/i, "--#{ext}.jpg")
             mv broken_file, new_file
             @log.recovery "    !!! RENAMED '#{broken_file}' to '#{new_file}'"

             # NOTE: write.filenames will always be a single file, so the "other_files" shouldn't be needed
             other_files =  writer.filenames - [broken_file]
             writer.filenames = [new_file] + other_files
             result = writer.write
          end

          if writer.errors.any?{|e| e =~ /Can.{0,5}t read ExifIFD data/}
            # Verify type of file, too
            # For
            #   Bad ExifOffset SubDirectory start
            #   http://owl.phy.queensu.ca/~phil/exiftool/faq.html#Q20
            #   exiftool -all= -tagsfromfile @ -all:all -unsafe -icc_profile bad.jpg
            cmd="exiftool -all= -tagsfromfile @ -all:all -unsafe -icc_profile '#{file_path}'"
            @log.error "TAG:  == Trying to fix by running `#{cmd}` first"
            @log.error `#{cmd}`
            if $?.success?
              @log.recovery "TAG:  ++ removed broken existing metadata!"
              @log.recovery "TAG:  ++ rewriting metadata"
              result = writer.write
              sleep 5 if result
            end
          end

          unless result
            @log.error "TAG: Tagging uncorrectably failed: '#{writer.errors}'\n\n\tfile: '#{file_path}'\n\tpost: '#{post[:url]}'\n\turl:  '#{url}'"
            require 'pry'; binding.pry unless writer.errors.first =~ /^Warning: \[Minor\]/
          end
        end

        @log.success "TAG: Tagged metadata for '#{file_path}'" if result
      end
      dl_dir
    end

    private

    ##------------
    ## A safe way in Ruby to download a file to disk using open-uri
    ## From: https://gist.github.com/janko-m/7cd94b8b4dd113c2c193
    ##------------
    require "open-uri"
    require "net/http"

    Error = Class.new(StandardError)

    DOWNLOAD_ERRORS = [
      SocketError,
      OpenURI::HTTPError,
      RuntimeError,
      URI::InvalidURIError,
      Error,
    ]

    def _download(url, max_size: nil)
      url = URI.encode(URI.decode(url))
      url = URI(url)
      raise Error, "url was invalid" if !url.respond_to?(:open)

      options = {}
      options["User-Agent"] = "MyApp/1.2.3"
      options[:content_length_proc] = ->(size) {
        if max_size && size && size > max_size
          raise Error, "file is too big (max is #{max_size})"
        end
      }

      downloaded_file = url.open(options)

      if downloaded_file.is_a?(StringIO)
        tempfile = Tempfile.new("open-uri", binmode: true)
        IO.copy_stream(downloaded_file, tempfile.path)
        downloaded_file = tempfile
      end

      downloaded_file

    rescue *DOWNLOAD_ERRORS => error
      raise if error.instance_of?(RuntimeError) && error.message !~ /redirection/
      raise Error, "download failed (#{url}): #{error.message}"
    end

  end
end

