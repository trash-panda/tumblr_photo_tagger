require 'spec_helper'
require 'tumblr_scarper/options_helper'
require 'tumblr_scarper/scarper'
require 'tmpdir'
require 'json'

RSpec.describe TumblrScarper::Scarper do
  include TumblrScarper::OptionsHelper

  let(:targets){ [] }
  let(:tumblr_client) { instance_double('tumblr_client') }
  before :all do
    @default_options = default_options
  end

  before :each do
    @cache_dir = Dir.mktmpdir('scarper_spec')
    options = @default_options.dup
    options[:dl_root_dir]    = @cache_dir
    options[:cache_root_dir] = options[:dl_root_dir]
    options[:delay] = 0
    options[:log].level = 0
    allow(Tumblr::Client).to receive(:new).and_return(tumblr_client)
    test_options = set_up_target_options(options, targets)
    @scarper = TumblrScarper::Scarper.new test_options
  end

  it "initializes without disaster" do
    expect(@scarper).not_to be nil
  end

  context "#scarp" do
    context "with a single post" do
      let(:targets) { [{:id=>"20056442123", :blog=>"oldbookillustrations"}] }
      let(:api_data) { JSON.parse(File.read('spec/fixtures/files/scarper/single--raw-api-results-offset-0.json')) }
      before :each do
        targets.each do |tgt|
          target     = tgt.dup
          blog       = target.delete(:blog)
          cache_dir  = File.join(@cache_dir,blog,'.cache', tgt.reject{|k,v| k==:blog}.map{|k,v| "#{k}=#{v}"}.join) 
          cache_file = File.join(cache_dir,'offset-0.json')

          expect(tumblr_client).to receive(:posts).with( blog, target.merge( {:limit=>20, :offset=>0}) ).and_return(api_data)
          expect(@scarper).to receive(:mkdir_p).with(cache_dir)
          expect(File).to receive(:open).with(cache_file,'w')
        end
      end

      it 'scarps without errors' do
        targets.each do |target|
          expect{ @scarper.scarp(target) }.not_to raise_error
        end
      end
    end
  end
end

