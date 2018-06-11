require 'pry'
require 'pp'
require 'json'
require 'yaml'

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

def download(url, max_size: nil)
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
  /^(pompadour)$/i => 'hair:\1'
}

DELETE_TAGS = [
  'Abigail', 'Adams', 'Dolley', 'Madison', 'Jensen', 'Lefevre', 'bois de boulogne', 'caroline', 'on a clear day you can see forever', 'mrs james frasier', 'merry-joseph blondel' , 
  'simon', 'raeburn', "Christie's", 'doucet', 
].map(&:downcase)
  
def all_tags(photos)
  t = photos.values.map{|x| x[:tags]}.flatten.sort
  tu = t.uniq
  max = tu.map{|x| x.size}.max
  tu.map{|x| x.ljust(max+1) + t.count{|y| y == x }.to_s }
end

def sanitize_tags(tags)
  tags.each do |tag|
    TAG_SUBS.each do |k,v|
    _tag = tag.dup
      tag.gsub!(k,v)
      tag.downcase!
    end
  tags.delete_if{|x| DELETE_TAGS.include?(x.downcase) }
  end
  tags.sort.uniq
end

def photo_data(photo,post,photo_src_field)
  {
    :tags     => sanitize_tags(post['tags']),
    :slug     => post['slug'],
    :caption  => post['photo-caption'],
    :url      => post['url'],
    :name     => post['tumblelog']['name'],
    :id       => post['id'],
    :date_gmt => post['date-gmt'],
    :format   => post['format'],
  }
end

def common_post_ops(post)
  url = ''
  entry = {}
  photos = {}
  photo_src_field = 'photo-url-1280'
  
  unless post.fetch('photos',[]).empty?
    # multiple photos in a post
    post['photos'].each do |photo|
      url    = photo[photo_src_field]
      offset = photo['offset'].to_s           
      photos[url]           = photo_data(photo,post,photo_src_field)
      photos[url][:slug]    = post['slug'] + "--#{offset}"        
      photos[url][:caption] = photo['caption'] unless  photo['caption'].empty?
    end
  else
    url = post[photo_src_field]
    if( post[photo_src_field] =~ /^http/ )
      photos[url] = photo_data(photo,post,photo_src_field)
    elsif post['type'] == 'regular'
      skipped_files[:regular] ||= []
      skipped_files[:regular] << file
      puts "------- skipping text-only post from #{file}"
      next
    elsif post['type'] == 'answer'
      skipped_files[:answer] ||= []
      skipped_files[:answer] << file
      puts "------- skipping answer post from #{file}"
      next
    else
      puts "======= no .photos, no .photo-url-1280"
      binding.pry
    end
  end
end

# process tumblrthree-downloaded json files
def process_json_files
  skipped_files = {}
  photos = {}
  files_count = 0
  
  # TODO: add a more general hook here
  Dir['*.json'].each do |file|
    files_count += 1
    post = JSON.parse File.read(file, :encoding => 'UTF-8')
    entry = common_data_ops(post)
    puts "#### files_count: #{files_count}"
    puts "#### photos.size: '#{photos.size}'"
    if ((files_count % 50) == 0)
      puts "#### all tags " + all_tags( photos ).join("\n")
    end
  end

  puts "== end of files"
  puts photos.to_yaml
  File.open( 'url-tags-downloads.yaml', 'w' ){|f| f.puts photos.to_yaml }
  
  skipped_files.each do |post_type,files|
    File.open( "_skipped__#{post_type}", 'w' ){|f| f.puts files.to_yaml }
  end
end 

require 'multi_exiftool'
require 'fileutils'
require 'nokogiri'
require 'date'
include  FileUtils::Verbose

process_json_files

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

download_dir = 'downloaded_files'
mkdir_p download_dir
photos = YAML.load_file 'url-tags-downloads.yaml'
photos.each do |url,post|
  puts "\n## #{url}"
  puts post.to_yaml
  puts '','----',''
  
  
  file = "#{post[:slug]}#{File.extname(url)}"
  file_path = File.join( download_dir, file )
  unless File.exists? file_path
    downloaded_file = download url
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
