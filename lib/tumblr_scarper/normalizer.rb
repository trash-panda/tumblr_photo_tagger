require 'fileutils'
require 'json'
require 'yaml'

module TumblrScarper
  class Normalizer
    include  FileUtils::Verbose
    attr_accessor :cache_dir
    def initialize(cache_dir=nil,options=nil)
      @cache_dir_root = cache_dir || File.join(Dir.pwd,'tumblr_scarper_cache')
      @options = options || {}
    end

    # TODO: read these from file?
    TAG_SUBS = {
      /^(\d\d\d\d)'s?$/ => 'decade/\1s',
      /^(\d\d\d\d)$/ => 'year/\1',
      /^(\d\dth) century$/i => 'century/\1',
      /^(Romantic Era)$/i => 'era:romantic',
      /^(cashmere shawl)$/i => 'shawl',
      /^court( (dress|gown))?$/i => 'dress:court dress',
      /^(colonies)$/i => 'colonial',

      /^(Extant garments|feathers|regency|shawl|waistcoat|undergarments|underwear|uniform|robe|fancy dress|neoclassical|couture|belle epoque|baroque|Directoire|Empire|colonial|georgian|edwardian|victorian)$/i => 'fashion:\1',
      /^(dres)$/i => 'dress',
      /^(bow|bows)$/i => 'fashion:bows',
      /^(spencer)$/i => 'spencer jacket',
      /^(spencer jacket|tailcoat)$/i => 'coat:\1',
      /^wedding (dress|gown)$/i => 'dress:wedding',
      /^george s\.? stuart$/i => 'George S. Stuart',
      /^sire /i => 'Sir ',
      /^(go;d)$/i => 'gold',
      /^(walking dress|hoop skirt|gown|dinner dress|court dress|court train|ball gown|morning dress|evening dress|evening dres)$/i => 'dress:\1',
      /^(ballet slippers|slippers)$/ => 'shoes:\1',
      /^(bonnet)$/i => 'hat:\1',
      /^(pompadour)$/i => 'hair:\1',
      /^h. thomson/ => 'artist/Hugh Thomson',
      /^sktech$/ => 'sketch',
    }

    DELETE_TAGS = [
      'Abigail', 'Adams', 'Dolley', 'Madison', 'Jensen', 'Lefevre', 'bois de boulogne', 'caroline', 'on a clear day you can see forever', 'mrs james frasier', 'merry-joseph blondel' ,
      'simon', 'raeburn', "Christie's", 'doucet',
    ].map(&:downcase)

    SLUG_SUBS = {
      /-posted-a-picture-to-the-patreon(-full-size)?/ => '',
    }

    def scarp_label(blog, tag=nil, type = nil)
      scarp_label = blog
      scarp_label += "/#{tag}" if tag
      scarp_label += "/#{type}" if type
      scarp_label
    end

    def scarped_post_metadata  cache_path
      posts = []
      files_count = 0
      Dir[File.join(cache_path,'*.json')].sort.each do |file|
        files_count += 1
        post = JSON.parse File.read(file, :encoding => 'UTF-8')
        posts += post
        puts "== #{post.size} #{posts.size}  #{file} "
      end
      posts
    end


    def normalize(blog, tag=nil, type = nil)
      scarp_label = scarp_label(blog,tag,type)
      cache_path = File.expand_path("#{scarp_label}", @cache_dir_root)
      mkdir_p cache_path

      # ---- start normalizing data
      posts           = scarped_post_metadata(cache_path)  # load scarped metadata
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
      print_summary(photos)
      # ---- end normalizing data

      cache_file  = File.join(cache_path, "url-tags-downloads.yaml")
      File.open( cache_file, 'w' ){|f| f.puts photos.to_yaml }

      skipped_posts.each do |post_type,files|
        file = File.join(cache_path, "_skipped__#{post_type}.yaml")
        File.open( file, 'w' ){|f| f.puts files.to_yaml }
      end
      cache_path
    end

    private

    def print_summary(photos)
      puts photos.to_yaml
      puts "#### all tags \n" + all_tags( photos ).join("\n")
      puts "#### total tags: #{all_tags( photos ).size}"
      puts "#### photos without tags: #{photos.select{|k,v| v[:tags].empty? }.size}"
      puts "#### photos.size: #{photos.size}"
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
        puts "------- skipping BANNED TAG photo posts from #{post['post_url']}"
        skipped_posts['BANNED_PHOTO_TAG'] ||= []
        skipped_posts['BANNED_PHOTO_TAG'] << post['post_url']
        post_photos.reject!{|k,v| true }
      end
    end

    def skip_untagged_post!(post_photos, skipped_posts)
      if @options['skip_untagged'] && post_photos.map{|k,x| x[:tags] }.any?(&:empty?)
        puts "------- skipping untagged photo posts from #{post['post_url']}"
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
    def sanitize_tags(tags)
      tags.each { |tag| TAG_SUBS.each { |k,v| tag.gsub!(k,v) } }
      tags.delete_if{|x| tags_blacklist.include?(x.downcase) }
      tags.delete_if{|x| !tags_whitelist.include?(x.downcase) } unless tags_whitelist.empty?
      tags.map!(&:downcase) if @options['lowercase_tags']
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
          require 'pry'; binding.pry
        end
      end
      str += "--#{offset}" if offset
      str
    end

    # Return a photo data structure that can be used to download and tag a single image
    def photo_data(photo,post,photo_src_field)
      data = {
        :tags     => sanitize_tags(post['tags']),
        :slug     => post['slug'],
        :caption  => post['caption'],
        :url      => post['post_url'] || post['short_url'] || post['url'],
        :source_url  => post['source_url'] || nil,
        :link_url => post['link_url'] || nil,
        :name     => post['blog_name'],
        :id       => post['id'],
        :date_gmt => post['date'],
        :timestamp => post['timestamp'],
        :format   => post['format'],
        :image_permalink => post['image_permalink'],
        :local_filename  => sanitize_slug(post),
      }
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
      photo_src_field = 'original_size'  # I think this is always 'original_size' now

      unless post.fetch('photos',[]).empty?
        # multiple photos in a post
        post['photos'].each do |photo|
          url    = photo[photo_src_field]['url']
          photos[url]           = photo_data(photo,post,photo_src_field)
          if post['photos'].size > 1
            offset = photo['offset'] || photo[photo_src_field]['url'].split('.')[-2].split('_')[-2][-1]
            photos[url][:local_filename] = sanitize_slug(post, offset)
            require 'pry'; binding.pry if photos[url][:local_filename] =~ /^--\d+/
          end
          photos[url][:caption] = photo['caption'] unless  photo['caption'].empty?
        end
      else
        url = post[photo_src_field]
        if( post[photo_src_field] =~ /^http/ )
          photos[url] = photo_data(photo,post,photo_src_field)
        elsif ['chat', 'quote', 'audio', 'link', 'video', 'text','answer','regular'].include?(post['type'])
          photos[:skipped_posts][post['type']] ||= []
          photos[:skipped_posts][post['type']] << post['post_url']
          puts "------- skipping #{post['type']} post from #{post['post_url']}"
        else
          puts "======= no .photos"
          require 'pry'
          binding.pry
        end
      end
      photos
    end

  end
end

