require 'fileutils'
require 'json'
require 'yaml'
require 'digest'
require 'tumblr_scarper/content_helpers'

module TumblrScarper
  class Normalizer
    include  FileUtils::Verbose
    def initialize(options)
      @options = options
      @log = @options.log
      @options = options || {}
    end

    SLUG_SUBS = {
      /-posted-a-picture-to-the-patreon(-full-size)?/ => '',
    }

    def scarped_post_metadata  cache_path
      posts = []
      files_count = 0
      Dir[File.join(cache_path,'offset-*.json')].sort.each do |file|
        files_count += 1
        post = JSON.parse File.read(file, :encoding => 'UTF-8')
        posts += post
        @log.info "== #{post.size} #{posts.size}  #{file} "
      end
      posts
    end


    def normalize(target)
      cache_dir = @options[:target_cache_dirs][target]
      mkdir_p cache_dir

      # ---- start normalizing data
      posts           = scarped_post_metadata(cache_dir)  # load scarped metadata
      photos          = {}
      skipped_posts   = {}
      local_filenames = {}
      posts.each do |post|
        post_photos = photos_from_post(post)
        remove_skipped_post_photos!(post_photos,skipped_posts)
        tally_localfilenames!(post_photos, local_filenames)
        photos.merge! post_photos
      end
      ###overwrite_hack(local_filenames, photos)  # added to prevent overwrites of theeternalrocks  TODO: add flag
      print_summary(photos, skipped_posts)
      # ---- end normalizing data

      cache_file  = File.join(cache_dir, "url-tags-downloads.yaml")
      File.open( cache_file, 'w' ){|f| f.puts photos.to_yaml }

      skipped_posts.each do |post_type,files|
        file = File.join(cache_dir, "_skipped__#{post_type}.yaml")
        File.open( file, 'w' ){|f| f.puts files.to_yaml }
      end
      cache_dir
    end

    private

    def print_summary(photos, skipped_posts=nil)
      log = ->(x){ @log.verbose(x) }
      if photos.empty?
        log = ->(x){ @log.warn(x) }
      end
      log.call photos.to_yaml
      log.call "#### all tags:"
      all_tags( photos ).each{ |tag| log.call("  #{tag}") }
      log.call "#### total tags: #{all_tags( photos ).size}"
      log.call "#### photos without tags: #{photos.select{|k,v| v[:tags].empty? }.size}"
      log.call "#### photos.size: #{photos.size}"
      if skipped_posts.empty?
        log.call "####    no skipped posts!"
      else
        log.call "#### skipped posts: #{skipped_posts.map{|k,v| v.size}.sum}"
        skipped_posts.each do |k,v|
          log.call "####     #{k}: #{v.size}"
        end
      end
    end


    def remove_skipped_post_photos!(post_photos, skipped_posts)
      post_photos[:skipped_posts].each do |k,v|
        skipped_posts[k] ||= []
        skipped_posts[k] += v
      end
      post_photos.delete_if{|k,v| k == :skipped_posts}

      skip_post_with_banned_tags!(post_photos, skipped_posts) unless @options['ban_posts_tagged'].to_a.empty?
      skip_untagged_post!(post_photos, skipped_posts) if @options['skip_untagged']
    end


    def skip_post_with_banned_tags!(post_photos, skipped_posts)
      if post_photos.any?{|k,v| v[:tags].any?{|x| @options['ban_posts_tagged'].to_a.include?(x) } }
        @log.warn "------- skipping BANNED TAG photo posts from #{post['post_url']}"
        skipped_posts['BANNED_PHOTO_TAG'] ||= []
        skipped_posts['BANNED_PHOTO_TAG'] << post['post_url']
        post_photos.reject!{|k,v| true }
      end
    end

    def skip_untagged_post!(post_photos, skipped_posts)
      if @options['skip_untagged'] && post_photos.map{|k,x| x[:tags] }.any?(&:empty?)
        @log.warn "------- skipping untagged photo posts from #{post['post_url']}"
        skipped_posts['UNTAGGED_PHOTO'] ||= []
        skipped_posts['UNTAGGED_PHOTO'] << post['post_url']
        post_photos.reject!{|k,v| true }
      end
    end

    def tally_localfilenames!(post_photos, local_filenames)
      post_photos.each do |k,v|
        filename = v[:local_filename]
        require 'pry'; binding.pry if filename.to_s.empty?
        local_filenames[filename] ||= 0
        local_filenames[filename] += 1
      end
    end

     ### added to prevent overwrites of theeternalrocks  TODO: add flag
    def overwrite_hack(local_filenames, photos)
      local_filenames.select{|k,v| v > 1 }.each do |name, _num|
        photos_w_dup_filenames = photos.select{|k,v| v[:local_filename] == name }.sort_by{|k,v| v[:timestamp] }.to_h
        seq_width = photos_w_dup_filenames.size.to_s.size
        idx=0
        photos_w_dup_filenames.values.reverse.each do |p|
          p[:local_filename] += '--z' + (idx+=1).to_s.rjust(seq_width,'0')
        end
      end
    end


    def all_tags(photos)
      t = photos.values.delete_if{|x| x.empty? }.map{|x| x[:tags]}.flatten.sort
      tu = t.uniq
      max = tu.map{|x| x.size}.max
      tu.map{|x| x.ljust(max+1) + t.count{|y| y == x }.to_s }
    end

    # tags not to include in the final tag list
    def tags_blacklist
      return @tags_blacklist if @tags_blacklist
      return @tags_blacklist = DELETE_TAGS + (@options['delete_tags'] || [])
    end

    # tags to include in the final taglist
    def tags_whitelist
      return @tags_whitelist if @tags_whitelist
      return [] unless @options['accept_tags']
      @tags_whitelist = @options['accept_tags'].map{|x| x.downcase}
    end

    # if tags_whitelist is not empty, all other tags are removed
    def sanitize_tags(orig_tags)
      tags = orig_tags.dup

      # This is now down at download time, with the TagNormalizer
      tags.map!(&:downcase) if @options['lowercase_tags']

      # NOTE SANITIZE
      # Very rarely posts, API can return posts with \n or \r in their tags
      # ex: https://allmesopotamia.tumblr.com/post/129128529693/rare-sumerian-chariot-figurine-3rd-2nd-ml-bc-a
      # These look like mistakes, where each line should be a tag
      # FIXME FIXME FIXME
      nlcr_tags = tags.select{|x| x=~ /\r|\n/ }
      unless nlcr_tags.empty?
        @log.error("tags contains newlines: #{nlcr_tags.to_yaml}")
        nlcr_tags.each do |nlcr_tag|
          idx = tags.index nlcr_tag
          tags.delete_at idx
          tags.insert idx, *nlcr_tag.split(/[\n\r]+/)
        end
        @log.recovery("corrected nlcr tags:\nOLD TAGS: #{orig_tags.to_yaml}\nNEW TAGS: #{tags.to_yaml}")
      end

      tags.sort.uniq
    end

    # Transforms slug into someting better-suited to a local filename
    # @params [String] slug a post slug
    # @return [String] suitable local filename
    def sanitize_slug(post, offset=nil)
      str = post['slug'].dup
      if str.empty?
        str = "#{post['blog_name']}--#{post['id']}"
      end
      SLUG_SUBS.each do |k,v|
        begin
          str.gsub!(k,v)
        rescue TypeError => e
          @log.error "TypeError: #{e.message}"
          require 'pry'; binding.pry
        end
      end
      if post['___scarper::liked']
        str = "#{post['blog_name'] || post.dig('blog','name') || 'UNKNOWN-BLOG-NAME' }---#{str}"
        timestamp_prefix = Time.at(post['liked_timestamp']).strftime('%Y%m%d-%H%M%S') 
        str = "#{timestamp_prefix}---#{str}"
      end

      str += "--#{offset}" if offset
      str
    end

    # Return a photo data structure that can be used to download and tag a single image
    def photo_data(photo,post,photo_src_field)
      post_title_excerpt_or_nil = [
        post['title'],
        post['excerpt'],
      ].grep_v(NilClass).join("&xd;&xa;")
      post_title_excerpt_or_nil = nil if post_title_excerpt_or_nil.to_s.empty?
      photo_caption_or_nil = (photo['caption'].empty? ? nil : photo['caption'])

      data = {
        :tags     => sanitize_tags(post['tags']),
        :slug     => post['slug'],

        # Individual photoset photos can have titles (Tumblr calls them 'captions')
        # NOTE: In our photo metadata, this will replace the post[:title] (if there was one)
        :title    =>  photo_caption_or_nil || post_title_excerpt_or_nil || nil,

        # legacy post type   field
        # ---------   -------
        # image       caption
        # link        excerpt and/or description
        # text        body (maybe also reblog.content?)
        :caption    => post['caption'] || post['description'] || post['body'] || nil,
        :url        => post['post_url'] || post['short_url'] || post['url'],
        :source_url => post['source_url'] || nil,
        :link_url   => post['link_url'] || nil,
        :name       => post['blog_name'],
        :id         => post['id'],
        :date_gmt   => post['date'],
        :timestamp  => post['timestamp'],
        :format     => post['format'],
        :image_permalink => post['image_permalink'],
        :local_filename  => sanitize_slug(post),
      }

      require 'pry'; binding.pry if post['type'] == 'photo' && data[:title] && !photo['caption']
      data
    end

    # Returns photos from a post as a Hash
    #
    # @return Hash[String,Hash]
    #    key            -> data
    #    ---               ----------------
    #    url            -> {photo_data}
    #    :skipped_posts -> {skipped posts}
    #
    #      skipped posts Hash:
    #        post_type -> [urls]
    def photos_from_post(post)
      url = ''
      photos = { :skipped_posts => {} }  # special key for skipped (non-photo) posts
      photo_src_field = 'original_size'  # I think this is always 'original_size' now  # FIXME: sometimes panorama_size is present and better

      post['excerpt'] = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post['excerpt']) if post['excerpt']
      post['description'] = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post['description']) if post['description']
      post['caption'] = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post['caption']) if post['caption']
      post['body'] = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(post['body']) if post['body']

      unless post.fetch('photos',[]).empty?
        # multiple photos in a post
        #
        # Legacy Photo Posts
        #
        # Multi-photo Photo posts, called Photosets, will send return multiple photo objects in the photos array.
        #
        # https://www.tumblr.com/docs/en/api/v2#postspost-id---fetching-a-post-neue-post-format#legacy-photo-posts
        photo_number = 1
        post['photos'].each do |photo|
          url         = photo[photo_src_field]['url']
          photos[url] = photo_data(photo,post,photo_src_field)
          if post['photos'].size > 1
            # Some photos come with an 'offset'  TODO I haven't found this in the API docs yet
            uniq_suffix = photo['offset']

            # https://64.media.tumblr.com/8ad04281bc48f2ff9ee06c4fba9f788d/tumblr_nz7qqvn7Ie1sg29ano2_r1_1280.jpg
            #                                                                                      ^^ ^^
            #
            # https://66.media.tumblr.com/4fe728e4d964c122b4076fd53b3a3bab/tumblr_p6ecom4XE31tx7g3jo3_640.jpg
            #                                                                         this number -^^
            # Update: The o3_ number doesn't seem to be in order of the photos:
            #
            #    https://lalunelaprune.tumblr.com/post/169899230724/sort-of-storyboard-im-working-on
            #
            # o2_r1 variant:
            #    https://allmesopotamia.tumblr.com/post/645877347092971520/i-saw-this-exercise-completed-in-latin-found
            #
            #
            unless uniq_suffix
              photo[photo_src_field]['url'].split('/').last.match( /\A.+o\d+_(?:r\d+_)?\d+\.[a-z]+\Z/ ) do |m|
                underscore_split = photo[photo_src_field]['url'].split('/')[-1].split('.')[-2].split('_')
                u = underscore_split.shift
                u = underscore_split.shift if u == 'tumblr' # Q: when is this needed? (A: see _r1 example above)
                post_hash = Digest::SHA256.hexdigest(u[0..-3].to_s)[0..6] # shorter, maybe prevents duplicates from reposts
                uniq_suffix = post_hash + '-' + photo_number.to_s.rjust(2,'0')
              end
            end

            # photoset_layout - an undocumented key from the legacy API's photo posts
            #
            #   https://ortiies.tumblr.com/post/612870791583940608/past-6pm-cryptid-hunter-shift-is-over-and-this
            #
            #  post['photos'][n]['original_size']['url']
            #
            #    n=0 "https://64.media.tumblr.com/9b109de07d672f851143df0297e02b87/0155a58231e03725-09/s1280x1920/5383eccd6821a7e6983f6280cde6454a96dd7ae6.jpg"
            #    n=1 "https://64.media.tumblr.com/3e483e75fc80fb5a0c6084f1f1f2fe3a/0155a58231e03725-e9/s1280x1920/9648b4d5e8220a0f9f35c73e9c5b8fe62c811580.jpg"
            #    n=2 "https://64.media.tumblr.com/0eb2083480837348dc0c5f715b8545b9/0155a58231e03725-fe/s1280x1920/60f6964a368dd5c3eec2f761d5eef813a6733abd.jpg"
            #    n=3 "https://64.media.tumblr.com/55cf1bde69221db56482884d3e39b56c/0155a58231e03725-ef/s1280x1920/6548c7fe8a36ea83c9215ab17c1f6ccc56a0804f.png"
            #    n=4 "https://64.media.tumblr.com/3c31f0fc390886efd3cd0eda6f37f6d4/0155a58231e03725-c1/s1280x1920/6cfa3e3c6c211608d1d1eef0400e52cce900111b.jpg"
            #
            #  u = "5383eccd6821a7e6983f6280cde6454a96dd7ae6" # 01
            #  sha1 = "6ff43a9-01"
            #
            unless uniq_suffix
              regex_patt = %r[\A(?<str>.+/(?<uniq_str>\h+)-(?<hex_order>\h+)/s\d+x\d+/\h+\.[a-z]+)\Z]
              photo[photo_src_field]['url'].match( regex_patt ) do |m|
                post_hash = m[:uniq_str][0..6]
                urls = post['photos'].map{|x| x['original_size']['url'] }
                order_list = []
                post['photoset_layout'].scan(/\d/) do |x|
                  w = x.to_i
                  u_slice = urls.slice(order_list.size,w).sort_by{|u| u.match(regex_patt){|mm| mm[:hex_order] }}.sort_by(&:hex)
                  order_list += u_slice
                end
                photo_order_number = order_list.index(m[:str])+1
                uniq_suffix = post_hash + '-' + photo_order_number.to_s.rjust(2,'0')
              end
            end

            unless uniq_suffix
              @log.error "No appropriate URL pattern found to determine uniq_suffix for photoset! (investigate with pry)"
              require 'pry'; binding.pry
            end

            @log.warn("Add uniq_suffix: #{uniq_suffix} (photo_number: #{photo_number})")
            photos[url][:local_filename] = sanitize_slug(post, uniq_suffix)
            require 'pry'; binding.pry if photos[url][:local_filename] =~ /^--\d+/
          end

          photo_number += 1
        end
      else
        url = post[photo_src_field]
        if( post[photo_src_field] =~ /^http/ )
          photos[url] = photo_data(photo,post,photo_src_field)
        elsif post['type'] == 'text'

          body = post['body']
          imgs = TumblrScarper::ContentHelpers.imgs(body)

          # Some text posts don't have an html 'body' with imgs, but keep them
          # in their ['trail'] key
          #
          #   https://sweet-metazoa.tumblr.com/post/129649791712/latimeria-chalumna"
          #
          if imgs.empty?
            ###if post['trail'].to_a.size == 1
            ###  body = post.dig('trail',0,'content')
            ###  imgs = TumblrScarper::ContentHelpers.imgs(body)
            ###elsif post['trail'].to_a.size > 1
            ###  @log.todo( "post has no imgs in body, and ['trail'] size >= 1!.  What should we do here?")
            ###  require 'pry'; binding.pry
              imgs = post['trail'].inject([]){ |m,x| m + TumblrScarper::ContentHelpers.imgs(x.dig('content')) }
            ###end
          end


          embedded_photos = imgs.map do |x|
            {
              'caption' => '',
              'original_size' => { 'url' => x['src'] },
            }
          end

          embedded_photos.each_with_index do |photo, idx|
            url =  photo['original_size']['url']
            data =  photo_data(photo,post,photo_src_field)
            data[:local_filename] += "-" +  (idx+1).to_s.rjust(2,'0')
            caption  = TumblrScarper::ContentHelpers.post_html_caption_to_markdown(body)
            unless caption.to_s.strip.empty?
              data[:caption] = caption
            end
            photos[url] = data
          end



        elsif ['chat', 'quote', 'audio', 'link', 'video', 'answer','regular'].include?(post['type'])
          photos[:skipped_posts][post['type']] ||= []
          photos[:skipped_posts][post['type']] << post['post_url']
          @log.debug "------- skipping #{post['type']} post from #{post['post_url']}"
        else
          @log.info "======= no .photos"
          require 'pry'
          binding.pry
        end
      end
      photos
    end

  end
end

