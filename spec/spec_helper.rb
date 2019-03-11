# frozen_string_literal: true

require 'bundler/setup'

require 'cocoapods'
require 'cocoapods/command/gen'
require 'cocoapods/generate'

#-----------------------------------------------------------------------------#

module Pod
  # Redirects the messages to an internal store.
  #
  module UI
    class << self
      undef puts, warn, print

      attr_accessor :output
      attr_accessor :warnings

      def puts(message = '')
        @output << "#{message}\n"
      end

      def warn(message = '', _actions = [])
        @warnings << "#{message}\n"
      end

      def print(message)
        @output << message
      end
    end
  end
end

#-----------------------------------------------------------------------------#

RSpec.configure do |config|
  config.before(:suite) do
    require 'spec_helper/prepare_spec_repos'
    cocoapods_generate_specs_prepare_spec_repos
  end

  config.before(:each) do
    Pod::UI.output = ''.dup
    Pod::UI.warnings = ''.dup
    CLAide::ANSI.disabled = true
    Pod::Config.instance = nil

    ENV['CP_REPOS_DIR'] = cocoapods_generate_specs_cp_repos_dir.to_s
    ENV['CLAIDE_DISABLE_AUTO_WRAP'] = '1'
  end

  config.around(:each) do |test|
    env = ENV.to_h.clone
    test.run
    ENV.replace(env)
  end

  config.around(:each, tmpdir: true) do |test|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        test.run
      end
    end
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.extend(Module.new do
    def describe_class_method(name, *args, &blk)
      describe ".#{name}", *args do
        let(:method_args) { [] }
        subject(name) do
          described_class.send(name, *method_args)
        end

        module_exec(&blk)
      end
    end

    def describe_method(name, *args, &blk)
      old_subject_name = instance_method(:subject).original_name
      describe "##{name}", *args do
        let(:method_args) { [] }
        subject(name) do
          prior_subject = old_subject_name ? send(old_subject_name) : super()
          prior_subject.send(name, *method_args)
        end

        module_exec(&blk)
      end
    end
  end)
end
