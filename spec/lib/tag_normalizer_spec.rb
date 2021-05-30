require 'spec_helper'
require 'tumblr_scarper/tag_normalizer'
require 'yaml'

RSpec.describe TumblrScarper::TagNormalizer do
  let(:tag_rules){ {} }

  before :each do
    @normalizer = TumblrScarper::TagNormalizer.new(tag_rules: tag_rules, log: DEFAULT_OPTIONS.log)
  end

  it "initializes without disaster" do
    expect(@normalizer).not_to be nil
  end

  context 'basic rules' do


    let(:expected_rejected_results) do
      YAML.load <<~YAML
      ---
      - lamasu
      - Greek Mythology
      - mythology:roman
      - mythology/mythology:norse
      - inktober2020
      - greek art
      - 3rd century bce
      - 19th Century fashion
      YAML
    end

    let(:expected_corrected_results) do
      YAML.load <<~YAML
      ---
      - lamassu
      - Greek Mythology
      - mythology:roman
      - mythology/mythology:norse
      - inktober2020
      - greek art
      - 3rd century bce
      - 19th Century fashion
      YAML
    end

    let(:input_tags) do
      YAML.load <<~YAML
      ---
      - lamasu
      - something we don't care about
      - Greek Mythology
      - mythology:roman
      - mythology/mythology:norse
      - inktober2020
      - greek art
      - 3rd century bce
      - dragon age
      - Dragon Age
      - 19th Century fashion
      - 'fashion:victorian'
      - Animal of the Week
      - stone figurine
      - clay figure
      - tlatilco figure
      - maternity figure
      - long hair
      - hair
      - greenhair
      - tree
      - old stone
      - '1940'
      - 1940s
      - doric
      - heels
      - burgundy heels
      - vintage necklace
      - dress:mini
      - flowing dress
      - art tutorial
      - 1920s fashion
      YAML
    end
    let(:tag_rules) do
      YAML.load <<~'YAML'
      ---
      reject:
        # filter out obvious garbage tags
        - !ruby/regexp /\A.*\b(your|is|it's|its|his|her|their|so|oh|too|we('d|'ve|'re)?|was|to|had|i('m|'d|'ve)?|have|not|im|sorry|a)\b.*/i
        - !ruby/regexp /\!/
        - dragon age
      correct:
        # translate mis-spellings
        !ruby/regexp /\bgodd?ess?(?:es)?\Z/i: goddess
        fashoin: fashion
        lamasu: lamassu
        # ensure plural (TODO: should these be singular instead?)
        !ruby/regexp /\A(?<word>webcomic|comic|forest|tree|stone|rock|ruin)\Z/i: '\k<word>s'
        !ruby/regexp /\bphoto\Z/: photography
        !ruby/regexp /\Aart (?<word>tutorial|advice|process)s?\Z/: 'art/process'

      transform:
        # preserve "ns/label", "ns/prefix:label", "prefix:label" tags
        # TODO: TEST THIS
        !ruby/regexp /\A(?i)(?<ns>([a-z]+/[a-z]+:|[a-z]+:))(?<label>.+)\Z/: '\k<ns>\k<label>'  # |
        ### transform "label prefix" into prefix:label" tags
        sub("\A(?i)(?<label>[^:/]+) (?<prefix>(?:\($namespaces)))\Z": "\k<prefix>/\k<prefix>:\k<label>") # |
        ##(scan("\\A(?i)(?:\($namespaces))[/:].+") | ascii_downcase) # // stop here on match
        !ruby/regexp /\A(.*) (fashion)\Z/i: '\2/\2:\1'  # //
        !ruby/regexp /\A(inktober) ?(.*)\Z/i: '\1/\1 \2'
        !ruby/regexp /\A(spx) ?(.*)\Z/i: 'SPX \2'
        !ruby/regexp /\A\d{4}s\Z/: 'decade/\0'
        !ruby/regexp /\A\d{4}\Z/: 'year/\0'
        !ruby/regexp /\A(.*) (art|mythology|architecture)\Z/i: '\2/\0'
        !ruby/regexp /\A(.*) (figurines?|figures?)\Z/i: 'figurines/figurine:\1'
        !ruby/regexp /\A([a-z]+) ?(hair)\Z/i: '\2/\2:\1'
        !ruby/regexp /\A(temple|palace|doric|ionic|corinthian|frieze|necropolis|monument|garden|catacombs)\Z/i: 'architecture/\1'
        !ruby/regexp /\A.*\b(?<word>slippers|boots|shoes|heels|flats)\Z/i: 'fashion/shoes/shoes:\k<word>'
        !ruby/regexp /\A(?<word>.+) (?<label>necklace)\Z/i: 'fashion/\k<label>/\k<label>:\k<word>'
        # TODO: revisit how dress is handled (inconsistent with other fashion:)
        !ruby/regexp /\Adress:(?<word>.+)|(?<word>.*\b(?:skirt|tights|dress))\Z/i: 'fashion/dress/\k<word>'
      select: {}
      YAML
    end

    let(:expected_transformed_results) do
      YAML.load <<~YAML
      ---
      - lamassu
      - mythology/mythology:greek
      - mythology/mythology:roman
      - mythology/mythology:norse
      - inktober/inktober 2020
      - art/greek
      - century/3rd century bce
      - fashion/19th Century fashion
      - animal of the week
      YAML
    end
    let(:expected_normalized_results) do
      YAML.load <<~YAML
      ---
      - lamasu
      - Greek Mythology
      - inktober2020
      - greek art
      - 3rd century bce
      YAML
    end

    it 'should have tag rules defined' do
      expect(@normalizer.tag_rules).not_to be_empty
    end

    it "transforms tags as expected" do
      cumulative_input_tags = @normalizer.reject(input_tags)
      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
      expect(@normalizer.transform(cumulative_input_tags)).to eq expected_transformed_results
      expect(false).to_be true
    end

    it "rejects tags as expected" do
      expect(@normalizer.reject(input_tags)).to eq expected_rejected_results
    end

    it "corrects tags as expected" do
      cumulative_input_tags = @normalizer.reject(input_tags)
      expect(@normalizer.correct(cumulative_input_tags)).to eq expected_corrected_results
    end


    it "selects tags as expected" do
      cumulative_input_tags = @normalizer.reject(input_tags)
      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
      expect(@normalizer.select(cumulative_input_tags)).to eq expected_selected_results
    end

    it "adds tags as expected" do
      cumulative_input_tags = @normalizer.reject(input_tags)
      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
      cumulative_input_tags = @normalizer.add(cumulative_input_tags)
      expect(@normalizer.add(cumulative_input_tags)).to eq expected_added_results
    end

    it "selects tags as expected" do
      cumulative_input_tags = @normalizer.reject(input_tags)
      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
      cumulative_input_tags = @normalizer.add(cumulative_input_tags)
      cumulative_input_tags = @normalizer.select(cumulative_input_tags)
      expect(@normalizer.select(cumulative_input_tags)).to eq expected_selected_results
    end

    it "normalizes tags as expected" do
      expect(@normalizer.normalize(input_tags)).to eq expected_normalized_results
    end

  end

end
