require 'spec_helper'
require 'tumblr_scarper/scarper'

RSpec.describe TumblrScarper::Scarper do
  before :all do
    @scarper = TumblrScarper::Scarper.new TMP_DIR
  end
  it "initializes without disaster" do
    expect(@scarper).not_to be nil
  end

  it "caches post data" do
    blog = 'enchantingimagery'
    tag  = 'my scan'
    blog = 'oldbookillustrations'
    tag  = 'h. thomson'
    path = @scarper.scarp(blog,tag)
    cache_path = File.join(Dir.pwd,TMP_DIR,blog,tag)
    expect(File.directory?(cache_path)).to eq(true)
    file_glob = Dir[File.join(cache_path,'*.json')]
    expect(File.file?(file_glob.first)).to eq(true)
    expect(file_glob.size).to be > 3
  end
end

