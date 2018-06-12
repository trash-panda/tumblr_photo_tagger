require "bundler/setup"
require "tumblr_scarper"
require 'fileutils'

TMP_DIR = 'tmp'

RSpec.configure do |config|
  include FileUtils::Verbose
  mkdir_p TMP_DIR

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
