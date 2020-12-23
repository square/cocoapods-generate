# frozen_string_literal: true

require 'cocoapods/generate'

module Pod
  class Command
    class Gen < Command
      self.summary = 'Generates Xcode workspaces from a podspec.'

      self.description = <<-DESC.strip_heredoc
        #{summary}

        pod gen allows you to keep your Podfile and podspecs as the single source of
        truth for pods under development. By generating throw-away workspaces capable of
        building, running, and testing a pod, you can focus on library development
        without worrying about other code or managing an Xcode project.

        pod gen works particularly well for monorepo projects, since it is capable of
        using your existing settings when generating the workspace, making each gen'ed
        project truly a small slice of the larger application.
      DESC

      def self.options
        super.concat(Generate::Configuration.options.map do |option|
          next unless option.cli_name

          flag = "--#{option.cli_name}"
          flag += "=#{option.arg_name}" if option.arg_name
          [flag, option.message]
        end.compact)
      end

      self.arguments = [
        CLAide::Argument.new(%w[PODSPEC DIR], false, true)
      ]

      # @return [Configuration]
      #         the configuration used when generating workspaces
      #
      attr_reader :configuration

      def initialize(argv)
        options_hash = Generate::Configuration.options.each_with_object({}) do |option, options|
          value =
            if option.name == :podspec_paths
              argv.arguments!
            elsif option.flag?
              argv.flag?(option.cli_name)
            else
              argv.option(option.cli_name)
            end

          next if value.nil?
          options[option.name] = option.coerce(value)
        end
        @configuration = merge_configuration(options_hash)
        super
      end

      def run
        UI.puts "[pod gen] Running with #{configuration.to_s.gsub("\n", "         \n")}" if configuration.pod_config.verbose?

        # this is done here rather than in the installer so we only update sources once,
        # even if there are multiple podspecs
        update_sources if configuration.repo_update?

        Generate::PodfileGenerator.new(configuration).podfiles_by_specs.each do |specs, podfile|
          Generate::Installer.new(configuration, specs, podfile).install!
        end

        remove_warnings(UI.warnings)
      end

      def validate!
        super

        config_errors = configuration.validate
        help! config_errors.join("\n    ") if config_errors.any?
      end

      private

      def merge_configuration(options)
        # must use #to_enum explicitly since descend doesn't return an enumerator on 2.1
        config_hashes = Pathname.pwd.to_enum(:descend).map do |dir|
          path = dir + '.gen_config.yml'
          next unless path.file?
          Pod::Generate::Configuration.from_file(path)
        end.compact

        options.delete(:podspec_paths) if options[:podspec_paths].empty? && config_hashes.any? { |h| h.include?(:podspec_paths) }

        env = Generate::Configuration.from_env(ENV)
        config_hashes = [env] + config_hashes
        config_hashes << options

        configuration = config_hashes.compact.each_with_object({}) { |e, h| h.merge!(e) }
        Pod::Generate::Configuration.new(pod_config: config, **configuration)
      end

      def remove_warnings(warnings)
        warnings.reject! do |warning|
          warning[:message].include? 'Automatically assigning platform'
        end
      end

      def update_sources
        UI.title 'Updating specs repos' do
          configuration.sources.each do |source|
            source = config.sources_manager.source_with_name_or_url(source)
            UI.titled_section "Updating spec repo `#{source.name}`" do
              source.update(config.verbose?)
              source.verify_compatibility!
            end
          end
        end
      end
    end
  end
end
