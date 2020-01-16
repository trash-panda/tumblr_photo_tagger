require 'spec_helper'
require 'tumblr_scarper/options_helper'
require 'tumblr_scarper/scarper'
require 'tmpdir'
require 'json'

RSpec.describe TumblrScarper::Scarper do
  include TumblrScarper::OptionsHelper

  let(:targets) do
#    [{
#      :blog => 'oldbookillustrations',
#      :tag  => 'h. thomson'
#    }]
    []
  end

  let(:tumblr_client) { instance_double('tumblr_client') }

  before :each do
    @cache_dir = Dir.mktmpdir('scarper_spec')
    options = default_optionsdup
    options[:dl_root_dir] = @cache_dir
    options[:cache_root_dir] = options[:dl_root_dir]
    allow(Tumblr::Client).to receive(:new).and_return(tumblr_client)
    test_options = set_up_target_options(options, targets)
    @scarper = TumblrScarper::Scarper.new test_options
  end


  it "initializes without disaster" do
    expect(@scarper).not_to be nil
  end

  context "scarps a single post" do
  let(:targets) do
    [{:id=>"20056442123", :blog=>"oldbookillustrations"}]
  end
    before :each do
      targets.each do |tgt|
        target = tgt.dup
        blog = target.delete(:blog)
        data = JSON.parse(File.read('spec/fixtures/files/scarper/offset-0.json'))
        expect(tumblr_client).to receive(:posts).with( blog, target.merge( {:limit=>20, :offset=>0}) ).and_return(data)
      end
    end
    it 'scarps without errors' do
      targets.each do |target|
        expect{ @scarper.scarp(target) }.not_to raise_error
      end
    end
    it 'scarps without errors' do
      targets.each { |target| path =  @scarper.scarp(target) }
    end
  end
end

