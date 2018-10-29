require 'fileutils'
require 'json'
require 'yaml'

module TumblrScarper
  class Normalizer
    include  FileUtils::Verbose
    attr_accessor :cache_dir
    def initialize(cache_dir=nil)
      @cache_dir_root = cache_dir || File.join(Dir.pwd,'tumblr_scarper_cache')
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

      posts = scarped_post_metadata(cache_path)  # load scarped metadata

      photos = {}
      skipped_posts = {}
      posts.each do |post|
        _photos = common_post_ops(post)
        _photos[:skipped_posts].each do |k,v|
          skipped_posts[k] ||= []
          skipped_posts[k] += v
        end
        photos.merge! _photos
      end
      photos.delete_if{|k,v| k == :skipped_posts }
      puts "#### photos.size: '#{photos.size}'"
      puts "#### all tags \n" + all_tags( photos ).join("\n")

      puts photos.to_yaml
      cache_file  = File.join(cache_path, "url-tags-downloads.yaml")
      File.open( cache_file, 'w' ){|f| f.puts photos.to_yaml }

      skipped_posts.each do |post_type,files|
        file = File.join(cache_path, "_skipped__#{post_type}.yaml")
        File.open( file, 'w' ){|f| f.puts files.to_yaml }
      end
      cache_path
    end

    private

    def all_tags(photos)
      t = photos.values.delete_if{|x| x.empty? }.map{|x| x[:tags]}.flatten.sort
      tu = t.uniq
      max = tu.map{|x| x.size}.max
      tu.map{|x| x.ljust(max+1) + t.count{|y| y == x }.to_s }
    end

    def sanitize_tags(tags)
      tags.each do |tag|
        TAG_SUBS.each do |k,v|
        _tag = tag.dup
          tag.gsub!(k,v)
          #tag.downcase!
        end
      tags.delete_if{|x| DELETE_TAGS.include?(x.downcase) }
      end
      tags.sort.uniq
    end

    # Transforms slug into someting better-suited to a local filename
    # @params [String] slug a post slug
    # @return [String] suitable local filename
    def sanitize_slug(slug)
      str = slug.dup
      SLUG_SUBS.each do |k,v|
        begin
          str.gsub!(k,v)
        rescue TypeError => e
          require 'pry'; binding.pry
        end
      end
      str
    end

    def photo_data(photo,post,photo_src_field)
      data = {
        :tags     => sanitize_tags(post['tags']),
        :slug     => post['slug'],
        :caption  => post['caption'],
        :url      => post['short_url'] || post['url'],
        :name     => post['blog_name'],
        :id       => post['id'],
        :date_gmt => post['date'],
        :format   => post['format'],
        :url      => post['post_url'],
        :image_permalink => post['image_permalink'],
        :local_filename  => sanitize_slug(post['slug']),
      }
    end

    def common_post_ops(post)
      url = ''
      photos = { :skipped_posts => {} }
      photo_src_field = 'original_size'

      unless post.fetch('photos',[]).empty?
        # multiple photos in a post
        post['photos'].each do |photo|
          url    = photo[photo_src_field]['url']
          photos[url]           = photo_data(photo,post,photo_src_field)
          if post['photos'].size > 1
            offset = photo['offset'].to_s
            photos[url][:slug]    = post['slug'] + "--#{offset}"
          end
          photos[url][:caption] = photo['caption'] unless  photo['caption'].empty?
        end
      else
        url = post[photo_src_field]
        if( post[photo_src_field] =~ /^http/ )
          photos[url] = photo_data(photo,post,photo_src_field)
        elsif ['text','answer','regular'].include?(post['type'])
          photos[:skipped_posts][post['type']] ||= []
          photos[:skipped_posts][post['type']] << post['post_url']
          puts "------- skipping #{post['type']} post from #{post['post_url']}"
        else
          puts "======= no .photos"
          binding.pry
        end
      end

      photos
    end

  end
end

