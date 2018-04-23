# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'inch_by_inch/rake_task'

RuboCop::RakeTask.new(:rubocop)
InchByInch::RakeTask.new(:inch)

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts = %w[--format progress]
  end

  task :integration do
    sh 'bundle', 'exec', 'bacon', 'spec/integration.rb', '-q'
  end

  namespace :integration do
    task :update do
      rm_rf 'spec/integration/tmp'
      sh('bin/rake', 'spec:integration') {}
      # Copy the files to the files produced by the specs to the after folders
      FileList['spec/integration/tmp/*/transformed'].each do |source|
        name = source.match(%r{tmp/([^/]+)/transformed$})[1]
        destination = "spec/integration/#{name}/after"
        rm_rf destination
        mv source, destination
      end
    end
  end
end

task :readme do
  contents = File.read('README.md')

  cli_usage = `bin/cocoapods-gen --help`
  contents.sub!(/(<!-- begin cli usage -->\n).+(\n<!-- end cli usage -->)/m, "\\1```\n#{cli_usage}```\\2")

  File.write 'README.md', contents
end

task spec: %w[spec:unit spec:integration]

task default: %w[spec rubocop inch readme]
