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
    let(:test_data) do
      YAML.load_file(File.expand_path('../fixtures/files/tag_normalizer/tests01.yaml',__dir__))
    end


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
      input = test_data['test_input']
      v = input.select{ |x|
        active_input_sets = YAML.load <<~YAML
        ---
        - general
        - namespaces
        ##- photography
        - art
        ##- years
        - anatomy
        - fashion
        #- inktober
        #- spx
        #- figurines
        #- history
        #- other design
        - hair
        #- character design
        YAML
        match = active_input_sets.include? x
        warn match ? "  -- input tags: set '#{x}'" :  "  -- input tags: EXCLUDING set '#{x}'"
        match
      }
      v.values.flatten
    end

    let(:tag_rules) do
      test_data['tag_rules']
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

##    it "transforms tags as expected" do
##      #cumulative_input_tags = @normalizer.reject(input_tags)
##      #cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
##      expect(@normalizer.transform(cumulative_input_tags)).to eq expected_transformed_results
##      expect(false).to_be true
##    end

##    it "rejects tags as expected" do
##      result_tags = input_tags.map{|tag| next@normalizer.reject?
##        require 'pry'; binding.pry
##      expect @normalizer.reject(input_tags)).to eq expected_rejected_results
##    end

##    it "corrects tags as expected" do
##      cumulative_input_tags = @normalizer.reject(input_tags)
##      expect(@normalizer.correct(cumulative_input_tags)).to eq expected_corrected_results
##    end
##
##
##    it "selects tags as expected" do
##      cumulative_input_tags = @normalizer.reject(input_tags)
##      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
##      expect(@normalizer.select(cumulative_input_tags)).to eq expected_selected_results
##    end
##
##    it "adds tags as expected" do
##      cumulative_input_tags = @normalizer.reject(input_tags)
##      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.add(cumulative_input_tags)
##      expect(@normalizer.add(cumulative_input_tags)).to eq expected_added_results
##    end
##
##    it "selects tags as expected" do
##      cumulative_input_tags = @normalizer.reject(input_tags)
##      cumulative_input_tags = @normalizer.correct(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.transform(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.add(cumulative_input_tags)
##      cumulative_input_tags = @normalizer.select(cumulative_input_tags)
##      expect(@normalizer.select(cumulative_input_tags)).to eq expected_selected_results
##    end

    it "normalizes tags as expected" do
      expect(@normalizer.normalize(input_tags)).to eq expected_transformed_results
      #expect(@normalizer.normalize(input_tags)).to eq expected_normalized_results
    end

  end

end
