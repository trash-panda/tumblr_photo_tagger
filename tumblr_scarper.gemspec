
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "tumblr_scarper/version"

Gem::Specification.new do |spec|
  spec.name          = "tumblr_scarper"
  spec.version       = TumblrScarper::VERSION
  spec.authors       = ["Trash Panda"]
  spec.email         = ["trash-panda@users.noreply.github.com"]

  spec.summary       = %q{Scrape, normalize, and tag photos from Tumblr}
  spec.description   = %q{Download a Tumblr's photos and add XMP tags using exiftool}
  spec.homepage      = 'https://github.com/trash-panda/tumblr-scarper'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "nothing.yet.thanks"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/.*tumblr.*}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "tumblr_client", "~> 0.8"
  spec.add_dependency "multi_exiftool", "~> 0.9"
  spec.add_dependency "nokogiri", "~> 1.6"
  spec.add_dependency "oauth", "~> 0.5"
  spec.add_dependency "logging", "~> 2.2"
  #spec.add_dependency "thor", "~> 0.20"
  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-mocks", "~> 3.0"
  spec.add_development_dependency "pry"
end
