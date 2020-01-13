require 'nokogiri'
module TumblrScarper
  class ContentHelpers

    def self.imgs(str)
      html = Nokogiri::HTML.fragment(str)
      html.css('img')
    end

    def self.post_html_caption_to_markdown(str)
      html = Nokogiri::HTML.fragment(str)
      a_links = []
      html.css('a').each do |a|
        text = a.inner_text
        a_links << a['href']
        a.replace "[#{text}][#{a_links.size - 1}]"
      end
      html.css('br').each do |_p|
        _p.replace "\n"
      end
      html.css('p').each do |_p|
        text = _p.inner_text
        _p.replace "#{text}\n"
      end
      html.css('blockquote').each do |_p|
        text = _p.inner_text.split("\n").map{|x| "> #{x}" }.join("\n")
        _p.replace "#{text}\n"
      end

      caption  = "#{html.to_str}\n#{a_links.each_with_index.map{|x,i| "[#{i}]: #{x}" }.join("\n")}".gsub("\n",'&#xd;&#xa;')
      caption
    end
  end
end
