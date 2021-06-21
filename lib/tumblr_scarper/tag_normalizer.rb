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
      paired_results = {}
      tags = tags.map do |tag|
        paired_results[tag] = ''
        next(nil) if reject?(tag)
        r_tag = correct(tag.downcase)
        r_tag = correct(r_tag.downcase, stage: 'ns')
        r_tag = transform_and_stop(r_tag) || select(r_tag)
        next(nil) unless r_tag
        #tags = add(tags)
        #tags = reject(tags) # second round of rejections in case we just recreated one?
        #tags = uniq(tags)
        paired_results[tag] = r_tag
        r_tag
      end.reject(&:nil?)

      kmax = paired_results.keys.map(&:size).max
      vmax = paired_results.values.map(&:size).max
      #warn paired_results.sort_by(&:last).to_h.map{|k,v| "#{v.ljust(vmax+1)} (#{k})" }.join("\n")
      warn paired_results.to_h.map{|k,v| "#{v.ljust(vmax+1)} < #{k}" }.join("\n")
      tags.uniq
    end

    def reject?(tag)
      @tag_rules['reject'].any? {|rule| tag.downcase.match?(rule)}
    end

    def correct(tag,stage: 'correct')
      @tag_rules[stage].inject(tag) do |tag,rule|
        rxp = rule[0]
        if rule[0].class == Regexp && rule.to_s.match?('%NAMESPACES')
          rxp = Regexp.new rule[0].to_s.gsub('%NAMESPACES%', @tag_rules['namespaces'])
        end

        if rxp.match? tag
          r_tag = tag.downcase.sub(rxp,rule[1])
          warn "  #{"(#{stage})".ljust(9)}   #{"'#{tag}'".ljust(27)} > #{"'#{r_tag}'".ljust(30)}"
          #warn "i              --> rule: '#{rule}'"
          r_tag
        else
          tag
        end
      end
    end

    def transform_and_stop(tag)
      matched = false

      t_tag = @tag_rules['transform'].inject(tag) do |tag,rule|
        rxp = rule[0]
        rxp = Regexp.new rule[0].to_s.gsub('%NAMESPACES%', @tag_rules['namespaces']) if rule[0].to_s.match?("%NAMESPACES%")
        @log.debug "(transform) tag: '#{tag}', rule: '#{rule}'"
        r_tag = tag

        if rxp.match? tag
          r_tag = tag.sub(rxp,rule[1])
          warn "  (transform) #{"'#{tag}'".ljust(27)} > #{"'#{r_tag}'".ljust(30)}" unless r_tag == tag
          matched = true
          break(r_tag)
        end
        r_tag
      end

      return t_tag if matched
      nil
    end

    def select(tag)
      @tag_rules['select'].each do |label, rxp|
        rxp = Regexp.new rxp.to_s.gsub('%NAMESPACES%', @tag_rules['namespaces']) if rxp.to_s.match?("%NAMESPACES%")
        if rxp.match?(tag)
          warn "  (select)    #{"'#{tag}'".ljust(27)} @  [ #{label} ]"
          return tag
        end
      end
      nil
    end

    def add(tags)
      require 'pry'; binding.pry
    end

    def uniq(tags)
      require 'pry'; binding.pry
    end
  end
end
