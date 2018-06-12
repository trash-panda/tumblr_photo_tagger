require 'spec_helper'
require 'tumblr_scarper/normalizer'

RSpec.describe TumblrScarper::Normalizer do
  before :all do
    @normalizer = TumblrScarper::Normalizer.new TMP_DIR
  end
  it "initializes without disaster" do
    expect(@normalizer).not_to be nil
  end

  it "caches photo data" do
    blog = 'enchantingimagery'
    tag  = 'my scan'
    blog = 'oldbookillustrations'
    tag  = 'h. thomson'
    path = @normalizer.normalize(blog,tag)

    cache_path = File.join(Dir.pwd,TMP_DIR,blog,tag)
    expect(path).to eq(cache_path)
    expect(File.directory?(cache_path)).to eq(true)
    file_glob = Dir[File.join(cache_path,'*.yaml')]
    expect(File.file?(file_glob.first)).to eq(true)
    expect(file_glob.size).to eq 1
  end
end

