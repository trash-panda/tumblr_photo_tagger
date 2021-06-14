require 'logging'

module TumblrScarper
  class TagNormalizer
    include  FileUtils::Verbose

    attr_reader :tag_rules
    def initialize(tag_rules:, log: Logging.logger[TumblrScarper::TagNormalizer])
      @tag_rules = tag_rules
      @log = log
    end


    # reject
    # correct
    # transform
    # select
    # add
    # uniq
    def normalize(tags)
      tags = reject(tags)
      tags = correct(tags)
      tags = transform(tags)
      tags = select(tags)
      tags = add(tags)
      tags = reject(tags) # second round of rejections in case we just recreated one?
      tags = uniq(tags)
    end

    def reject(tags)
      tags.reject{ |tag| @tag_rules['reject'].any? {|rule| tag.downcase.match?(rule)} }
    end

    def correct(tags)
      tags.map do |tag|
        @tag_rules['correct'].inject(tag) do |tag,rule|
          @log.debug "(correct) tag: '#{tag}', rule: '#{rule}'"
          tag.sub(rule[0],rule[1])
        end
      end
    end

    def transform(tags)
      paired_results = {}
      results = tags.map do |tag|
        r_tag = @tag_rules['transform'].inject(tag) do |tag,rule|
          @log.debug "(transform) tag: '#{tag}', rule: '#{rule}'"
          tag.downcase.sub(rule[0],rule[1]) # TODO should this always downcase?
        end
        paired_results[tag] = r_tag
        r_tag
      end

      kmax = paired_results.keys.map(&:size).max
      vmax = paired_results.values.map(&:size).max
      warn paired_results.sort_by(&:last).to_h.map{|k,v| "#{v.ljust(vmax+1)} (#{k})" }.join("\n")
        #require 'pry'; binding.pry
        results
    end

    def select(tags)
      require 'pry'; binding.pry
    end

    def add(tags)
      require 'pry'; binding.pry
    end

    def uniq(tags)
      require 'pry'; binding.pry
    end
  end
end
