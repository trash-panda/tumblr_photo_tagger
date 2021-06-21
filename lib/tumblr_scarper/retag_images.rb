require 'logging'
require 'tumblr_scarper/tag_normalizer'
require 'tumblr_scarper/content_helpers'
require 'yaml'
require 'multi_exiftool'

module TumblrScarper
  class RetagImages
    include  FileUtils::Verbose

    attr_reader :tag_rules

    KEYWORD_TAGS_TO_REMOVE = [
      'XMP-mediapro:CatalogSets',
      'XMP-lr:HierarchicalSubject',
      'XMP-digiKam:TagsList',
      'XMP-microsoft:LastKeywordXMP',
      'XMP-acdsee:Categories',
    ]

    CAPTION_TAGS_TO_REMOVE = [
      'XMP-acdsee:Notes',
      'XMP-exif:UserComment',
      'XMP-tiff:ImageDescription',
    ]


    def initialize(options)
      @options = options
      @tag_rules = options.tag_rules
      @log = options.log
      @tag_normalizer = TumblrScarper::TagNormalizer.new(tag_rules: @tag_rules, log: @log)
      @exiftool_config = File.join(__dir__,'files','.ExifTool_config')
    end

    def exiftool_reader_for(path)
      reader = MultiExiftool::Reader.new
      reader.filenames = path # file or directory, since we're using -recurse
      reader.config = @exiftool_config
      reader.options = {
        'P' => true, 'E' => true,
        'recurse' => true,
        'use' => 'MWG',
        'g1' => true,
      }
      reader
    end

    def exiftool_writer_for(file_path)
      writer = MultiExiftool::Writer.new
      writer.filenames = file_path
      writer.config = @exiftool_config
      writer.options = { 'P' => true, 'E' => true }
      writer.overwrite_original = true
      writer
    end

    def prepare_tag_data(post)
      writer_values = {}

      if post[:caption]
        CAPTION_TAGS_TO_REMOVE.each do |tag|
          writer_values[tag] = ''
        end
        writer_values['MWG:description']= TumblrScarper::ContentHelpers.to_exiftool_newlines(post[:caption])
      end

      if post[:keywords]
        # Remove conflicting tag lists set by digikam
        KEYWORD_TAGS_TO_REMOVE.each do |tag|
          writer_values[tag] = ''
        end

        writer_values['MWG:Keywords'] = post[:keywords]
        if post[:keywords].empty?
          writer_values['MWG:Keywords'] = ''
        end
      end

      if post[:tumblr_tags]
        writer_values['XMP-tumblr:TumblrTags'] = post[:tumblr_tags]
      end

      writer_values
    end

    def write_metadata_to_file( file_path, post, file_mtime )
      @log.verbose "Updating #{post.keys.map(&:to_s).join(', ')} in #{file_path}..."
      writer = exiftool_writer_for(file_path)
      writer.values = prepare_tag_data(post)
      result = writer.write
      unless result || writer.errors.first =~ /\d image files updated$/
        if writer.errors.first =~ /^Warning: \[Minor\]/i # rubocop:disable Style/Semicolon, Lint/Debugger
          @log.verbose('  TAG: Continuing because this is a minor error')
        elsif writer.errors.first =~ /Warning: Some character\(s\) could not be encoded in Latin/
          @log.verbose("  TAG: Continuing because AFAICT, the characters are usually emoji and usually still work in captions")
        else
          @log.error "TAG: Tagging failed: '#{writer.errors}'"
          @log.todo("This error isn't handled.  If pry is installed, investigate it")
          require 'pry'; binding.pry
        end
      end

      touch file_path, mtime: file_mtime # Preserve file mtime
      @log.success "Updated #{post.keys.map(&:to_s).join(', ')} in #{file_path}"
    end

    def retag_paths(paths)
      paths.each{|path| retag_path(path) }
    end

    def ensure_tags_in_description(tags, caption)
      taglined_caption = TumblrScarper::ContentHelpers.taglined_caption(
        tags: tags,
        caption: caption
      )
    end

    def sanitize_keywords(keywords)
      return nil unless keywords
      keywords = [keywords] if keywords.is_a?(String)
      keywords = [keywords.to_s] unless keywords.is_a?(Array)
      keywords.map!(&:to_s) if keywords
      if !keywords.is_a?(Array) || keywords.any?{|x| !x.is_a?(String) }
        @log.error( "UNEXPECTED: keywords is not an Array of Strings: #{keywords.to_yaml}" )
        require 'pry'; binding.pry
      end
      keywords
    end

    def retag_path(path)
        require 'fileutils'
        require 'date'
        spn = 0
        paths = File.join(path,'*')
        Dir[paths].each do |sub_path|
          sub_paths = Dir[File.join(sub_path,'*')]
          spn += 1
          next if sub_path =~ %r[/(airfortress)\Z]
          @log.warn("== == (#{spn}/#{paths.size}) #{sub_path} (#{sub_paths.size}) == ==")
          reader = exiftool_reader_for(sub_path)
          results = reader.read
          #puts "ARGS:", reader.exiftool_args
          unless reader.errors.reject{|x| x.empty? || x =~ /image files read\Z/ }.empty?
            @log.error ("ERRORS READING FILE METADATA: #{reader.errors.to_yaml}")
            require 'pry'; binding.pry
          end

          results.each do |img|
            next unless img['sourcefile'] =~ /\.(jpg|jpeg|png|gif)\Z/i
            mwg_keywords = sanitize_keywords (img['MWG']||{})['keywords']
            tumblr_tags = sanitize_keywords (img['xmptumblr']||{})['tumblrtags']
            caption = (img['MWG']||{})['description']
            caption = caption.to_s if caption
            post = {} # caption, tags

            unless mwg_keywords || tumblr_tags
              @log.verbose("-- No MWG or Tumblr tags: #{img['sourcefile']}; skipping")
              next
            end
            @log.info( "\n====== img: #{img['sourcefile']}" )


            if tumblr_tags #mwg_keywords && tumblr_tags
              @log.debug( "case: MWG keyoard && TumblrTags: #{img['sourcefile']}" )
              desc_with_tags = ensure_tags_in_description(tumblr_tags, caption)
              puts desc_with_tags

              if caption.gsub(/\r\n/,"\n") == desc_with_tags
                CAPTION_TAGS_TO_REMOVE.any? do |tag|
                  tag_ns = tag.split(':').first.downcase.sub('-','')
                  tag_name = tag.split(':').last.downcase.sub('-','')
                  if img[tag_ns] && img[tag_ns][tag_name]
                    @log.warn "Found digikam caption poop '#{tag}'; forcing caption update"
                    post[:caption] = desc_with_tags
                  end
                end
              else
                post[:caption] = desc_with_tags
                unless desc_with_tags.gsub(/[\r\n]+---[\r\n]+Tags:.*\Z/,'') == caption.gsub(/\r\n|\r/,"\n").rstrip
                  @log.error("UNEXPECTED: desc_with_tags came out differently than caption; find out why!")
                  require 'pry'; binding.pry
                end
              end

              new_mwg_keywords = @tag_normalizer.normalize(tumblr_tags)
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
            # FIXME remove
                bad_patt = /(costume|fashion|history):/

              # Try to preserve valid keywords added by external tools
              if mwg_keywords
                processed_mwg_keywords = @tag_normalizer.normalize(mwg_keywords)
                processed_mwg_keywords.reject!{|x| x =~ bad_patt }
                missing_mwg = processed_mwg_keywords - new_mwg_keywords
                unless missing_mwg.empty?
                  @log.error "#{img['sourcefile']}: New tags would remove valid MWG tags: #{missing_mwg.to_yaml}\n"
                  missing_mwg.map!{|x| x.sub(%r[\Ayear/(?<year>\d+) BCE\Z]i, 'year/\k<year> BCE')}
                  missing_mwg.map!{|x| x.sub(%r[\Ayear/(?<year>\d+) CE\Z]i, 'year/\k<year> CE')}
                  new_mwg_keywords += missing_mwg
                  new_mwg_keywords.uniq!
                  @log.recovery "Adding valid MWG tags back: #{missing_mwg.to_yaml}\n"

                  remove_digikam_poop = KEYWORD_TAGS_TO_REMOVE.any? do |tag|
                    tag_ns = tag.split(':').first.downcase.sub('-','')
                    tag_name = tag.split(':').last.downcase.sub('-','')
                    if img[tag_ns] && img[tag_ns][tag_name]
                      @log.warn "Found digikam keywords poop '#{tag}'; forcing keywords update"
                      post[:keywords] = new_mwg_keywords
                    end
                  end
                end
              end
              if new_mwg_keywords.any?{|x| x =~ bad_patt }
                @log.fatal "FORCING KEYWORD REMOVAL"
                post[:keywords] = new_mwg_keywords.reject{ |x| x=~ bad_patt }
              end

              unless new_mwg_keywords.sort == (mwg_keywords||[]).sort
                post[:keywords] = new_mwg_keywords
              else
                @log.happy("MWG Tags unchanged: #{new_mwg_keywords.join(', ')}")
              end

            else
              mwgk = mwg_keywords ? 'y' : 'n'
              tmbk = tumblr_tags ? 'y' : 'n'
              @log.todo "NOT YET IMPLEMENTED: [MWG keywords: #{mwgk} | Tumblr keywords: #{tmbk}] - Case not handled yet"
              ###require 'pry'; binding.pry
            end

            # if changed, write metadata back io image
            if post.empty?
              @log.happy("Tags & caption unchanged; no need to change file!")
            else
              @log.info "METADATA CHANGED: write to file: #{post.to_yaml}"
              write_metadata_to_file( img['sourcefile'], post, img['system']["filemodifydate"])
            end
          end
      end
    end
  end
end

