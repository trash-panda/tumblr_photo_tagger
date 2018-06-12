require 'spec_helper'
require 'tumblr_scarper/downloader'

RSpec.describe TumblrScarper::Downloader do
  before :all do
    @downloader = TumblrScarper::Downloader.new TMP_DIR
  end
  it "initializes without disaster" do
    expect(@downloader).not_to be nil
  end

  it "downloads and tags photos" do
    blog = 'enchantingimagery'
    tag  = 'my scan'
    blog = 'oldbookillustrations'
    tag  = 'h. thomson'
    path = @downloader.download(blog,tag)

    cache_path = File.join(Dir.pwd,TMP_DIR,blog,tag)
    expect(path).to eq(cache_path)
    expect(File.directory?(cache_path)).to eq(true)
    fail 'mock web server for downloader'
    fail 'write some tests'
  end
end

