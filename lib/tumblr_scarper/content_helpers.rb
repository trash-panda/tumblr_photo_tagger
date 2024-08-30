require 'nokogiri'
require 'logging' # FIXME
module TumblrScarper
  class ContentHelpers

    def self.imgs(str)
      html = Nokogiri::HTML.fragment(str)
      html.css('img')
    end

    # Generate suffix
    def self.taglined_caption(tags:, caption:)
      caption = caption.sub(/[\r\n]{2}---[\r\n]+Tags:.*\Z/m, '')
      caption = caption.gsub(/\r\n|\n|\r/, "\n")
      tagline = tags.map{|x| x.sub(/^/,'#')}.join(', ')
      tagline = "Tags: #{tagline}"
      tagline = "\n\n---\n#{tagline}" unless caption.empty?
      [caption.to_s.rstrip,tagline].join.strip
    end

    def self.to_exiftool_newlines(str)
      str.gsub(/\r\n|\n|\r/,'&#xd;&#xa;')
    end


    def self.inner_html_caption_to_markdown(html, a_links)
      html.css('a').each do |a|
        text = a.inner_text
        a_links << a['href']
        a.replace "[#{text}][#{a_links.size - 1}] "
      end

      html.css('br').each do |_p|
        _p.replace "\r"
      end

      html.css('blockquote').each do |_p|
        #require 'pry'; binding.pry
        text = _p.inner_text.split(/\r\n|\r|\n/).map{|x| "> #{x}" }.join("\n>\n")
        _p.replace "#{text}\n"
      end

      html.css('p').each do |_p|
        # text = _p.inner_text
        text = _p.inner_text.gsub(/(?:\G|\A)\n/,"\r")
        text.gsub!(/ *$/,'')
        text.gsub!(/\n+/,' ')   # Remove line breaks from the html
        text.gsub!("\r","\n")
        _p.replace "#{text}\r\r"
      end

      html
    end

    # Converts html into simplistic markdown
    def self.post_html_caption_to_markdown(str)
      log = Logging.logger[TumblrScarper] # FIXME
      if str.nil?
        log.todo "Somehow `str` is nil; investigate why!"
        require 'pry'; binding.pry
      end

      html = Nokogiri::HTML.fragment(str.to_s.strip)
      a_links = [] # List of urls for reference-style links (.e.g, `[hobbit-hole][1]`)

      html = inner_html_caption_to_markdown(html, a_links)

      caption_str = html.to_str
      caption_str.gsub! /\r\n/, "\n"      # Remove extra line in EOL + <br>
      caption_str.gsub! "\r", "\n"        # Make all EOLs into \n
      caption_str.gsub! /[ \n\r]+\Z/, ''  # Strip spaces from the end
      caption_str.strip!

      caption_str.gsub! /\n{3,}/, "\n\n"  # Compress newlines
      caption_str.gsub! /(?:\n> ?){3,}\n>( ?)/, "\n>\n>\n>\\1"  # Compress blockquotes

      # Reference-style markdown Links
      #
      # https://www.markdownguide.org/basic-syntax/#reference-style-links
      reference_link_block = a_links.each_with_index.map{|url,label| "[#{label}]: #{url}" }.join("\n")
      unless a_links.empty?
        reference_link_block = "\n" + reference_link_block
      end

      caption  = [
        caption_str,
        reference_link_block,
      ].join("\n")

      caption.chomp!

      STDERR.puts(caption)

      # Replacing "\n" with '&#xd;&#xa;' allows line breaks on windows:
      to_exiftool_newlines(caption)
    end
  end
end
