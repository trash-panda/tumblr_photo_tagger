require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec


desc 'Update default tag rules from spec test data'
task :update_default_tag_rules do 
  require 'yaml'
  src_file = 'spec/fixtures/files/tag_normalizer/tests01.yaml'
  dest_file = 'lib/tumblr_scarper/data/default_tag_rules.yaml'
  data = YAML.load_file(src_file)
  File.open(dest_file,'w'){|f| f.puts data['tag_rules'].to_yaml }
  puts "Updated '#{dest_file}' from '#{src_file}['tag_rules']'"

end
