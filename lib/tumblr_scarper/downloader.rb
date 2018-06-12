require 'yaml'

require 'multi_exiftool'
require 'fileutils'
require 'nokogiri'
require 'date'

include  FileUtils::Verbose
module TumblrScarper
  class Downloader
    include  FileUtils::Verbose
    attr_accessor :cache_dir
    def initialize(cache_dir=nil)
      @cache_dir_root = cache_dir || File.join(Dir.pwd,'tumblr_scarper_cache')
    end

    def scarp_label(blog, tag=nil, type = nil)
      scarp_label = blog
      scarp_label += "/#{tag}" if tag
      scarp_label += "/#{type}" if type
      scarp_label
    end

    def normalized_photo_metadata  cache_path
      posts = []
      files_count = 0
      photos = YAML.load_file File.join(cache_path,"url-tags-downloads.yaml")
    end

    def download(blog, tag=nil, type = nil, limit = 20, offset = 0 )
      scarp_label = scarp_label(blog,tag,type)
      cache_path = File.expand_path("#{scarp_label}", @cache_dir_root)
      mkdir_p cache_path

      photos = normalized_photo_metadata(cache_path) # load photo metadata

      download_dir = File.join(cache_path, 'downloaded_files')
      mkdir_p download_dir
      photos.each do |url,post|
        puts "\n## #{url}"
        puts post.to_yaml
        puts '','----',''

        file = "#{post[:slug]}#{File.extname(url)}"
        file_path = File.join( download_dir, file )
        unless File.exists? file_path
          downloaded_file = _download url
          cp downloaded_file, file_path
        end

        post_datetime = DateTime.parse(post[:date_gmt])

        caption  = post_html_caption_to_markdown(post)

        writer = MultiExiftool::Writer.new
        writer.filenames = file_path
        writer.options = { 'P' => true, 'E' => true }
        writer.overwrite_original = true

        writer.values = {
        'exif:imagedescription' => caption,
        'xmp:description'       => caption,
        'xmp:source'            => url,
        'xmp:relation'          => post[:url],
        'xmp:credit'            => post[:url],
        'xmp:subject'           => post[:tags],
        'xmp:createdate'        => post_datetime,
        }
        result = writer.write
        touch file_path, mtime: Time.parse(post_datetime.to_s)

        puts caption.gsub('&#xd;&#xa;',"\n")

        unless result || writer.errors.first =~ /\d image files updated$/
          warn "WARNING: Tagging failed: '#{writer.errors}'"
        end
      end
      download_dir
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
    ##-------------

    def post_html_caption_to_markdown(post)
      html = Nokogiri::HTML.fragment(
        post[:caption]
      )
      a_links = []
      html.css('a').each do |a|
        parent = a.parent
      text = a.inner_text
      a_links << a['href']
      a.replace "[#{text}][#{a_links.size - 1}]"
      end
      html.css('p').each do |_p|
        parent = _p.parent
      text = _p.inner_text
      _p.replace "#{text}\n"
      end
      html.css('blockquote').each do |_p|
        parent = _p.parent
        text = _p.inner_text.split("\n").map{|x| "> #{x}" }.join("\n")
        _p.replace "#{text}\n"
      end

      caption  = "#{html.to_str}\n#{a_links.each_with_index.map{|x,i| "[#{i}]: #{x}" }.join("\n")}".gsub("\n",'&#xd;&#xa;')
    end
  end
end

