require 'spec_helper'
require 'tumblr_scarper/scarper'

RSpec.describe TumblrScarper::Scarper do
  before :all do
    @scarper = TumblrScarper::Scarper.new
  end
  it "initializes without disaster" do
    expect(@scarper).not_to be nil
  end

  it "does something useful" do
    path = @scarper.scarp('enchantingimagery', 'my scan')
              require 'pry'; binding.pry
    expect(false).to eq(true)
  end
end

