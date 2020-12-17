# frozen_string_literal: true

module Pod
  module Generate
    class Configuration
      @options = []
      class << self
          # @return [Array<Option>]
          #         all of the options available in the configuration
          #
          attr_reader :options
      end

      Option = Struct.new(:name, :type, :default, :message, :arg_name, :validator, :coercer) do
        def validate(value)
          return if value.nil?
          errors = []
          if (exceptions = Array(value).grep(Exception)) && exceptions.any?
            errors << "Error computing #{name}"
            errors.concat exceptions.map(&:message)
          else
            errors << "got type #{value.class}, expected object of type #{Array(type).join('|')}" unless Array(type).any? { |t| t === value }
            validator_errors = begin
                                   validator && validator[value]
                                 rescue StandardError
                                   "failed to run validator (#{$ERROR_INFO})"
                                 end
            errors.concat Array(validator_errors) if validator_errors
            errors.unshift "#{value.inspect} invalid for #{name}" if errors.any?
          end
          errors.join(', ') unless errors.empty?
        end

        def cli_name
          return unless message
          @cli_name ||= name.to_s.tr '_', '-'
        end

        def flag?
          arg_name.nil?
        end

        def coerce(value)
          coercer ? coercer[value] : value
        end
      end
      private_constant :Option

      # Declares a new option
      #
      # @!macro [attach] $0
      #   @attribute [r] $1
      #     @return [$2] $4
      #     defaults to `$3`
      #
      def self.option(*args)
        options << Option.new(*args)
      end
      private_class_method :option

      # @visibility private
      #
      # Implements `===` to do type checking against an array.
      #
      class ArrayOf
        attr_reader :types

        def initialize(*types)
          @types = types
        end

        def to_s
          "Array<#{types.join('|')}>"
        end

        # @return [Boolean] whether the given object is an array with elements all of the given types
        #
        def ===(other)
          other.is_a?(Array) && other.all? { |o| types.any? { |t| t === o } }
        end
      end
      private_constant :ArrayOf

      # @visibility private
      #
      # Implements `===` to do type checking against a hash.
      #
      class HashOf
        attr_reader :key_types, :value_types

        def initialize(keys:, values:)
          @key_types = keys
          @value_types = values
        end

        def to_s
          "Hash<#{key_types.join('|')} => #{value_types.join('|')}}>"
        end

        # @return [Boolean] whether the given object is a hash with elements all of the given types
        #
        def ===(other)
          other.is_a?(Hash) && other.all? do |key, value|
            key_types.any? { |t| t === key } &&
              value_types.any? { |t| t === value }
          end
        end
      end
      private_constant :HashOf

      coerce_to_bool = lambda do |value|
        if value.is_a?(String)
          value =
            case value.downcase
            when ''
              nil
            when 'true'
              true
            when 'false'
              false
            end
        end
        value
      end

      coerce_to_pathname = lambda do |path|
        path && Pathname(path).expand_path
      end

      BOOLEAN = [TrueClass, FalseClass].freeze
      private_constant :BOOLEAN

      option :pod_config, Config, 'Pod::Config.instance', nil

      option :podfile_path, [String, Pathname], 'pod_config.podfile_path', 'Path to podfile to use', 'PATH', ->(path) { 'file does not exist' unless path.file? }, coerce_to_pathname
      option :podfile, [Podfile], 'Podfile.from_file(podfile_path) if (podfile_path && File.file?(File.expand_path(podfile_path)))'
      option :use_podfile, BOOLEAN, '!!podfile', 'Whether restrictions should be copied from the podfile', nil, nil, coerce_to_bool
      option :use_podfile_plugins, BOOLEAN, 'use_podfile', 'Whether plugins should be copied from the podfile', nil, nil, coerce_to_bool
      option :podfile_plugins, HashOf.new(keys: [String], values: [NilClass, HashOf.new(keys: [String], values: [TrueClass, FalseClass, NilClass, String, Hash, Array])]),
             '(use_podfile && podfile) ? podfile.plugins : {}',
             nil,
             nil,
             nil,
             ->(hash) { Hash[hash] }

      option :lockfile, [Pod::Lockfile], 'pod_config.lockfile', nil
      option :use_lockfile, BOOLEAN, '!!lockfile', 'Whether the lockfile should be used to discover transitive dependencies', nil, nil, coerce_to_bool
      option :use_lockfile_versions, BOOLEAN, 'use_lockfile', 'Whether versions from the lockfile should be used', nil, nil, coerce_to_bool

      option :use_libraries, BOOLEAN, 'false', 'Whether to use libraries instead of frameworks', nil, nil, coerce_to_bool

      option :generate_multiple_pod_projects, BOOLEAN, 'false', 'Whether to generate multiple Xcode projects', nil, nil, coerce_to_bool
      option :incremental_installation, BOOLEAN, 'false', 'Whether to use incremental installation', nil, nil, coerce_to_bool

      option :gen_directory, [String, Pathname], 'Pathname("gen").expand_path', 'Path to generate workspaces in', 'PATH', ->(path) { 'path is file' if path.file? }, coerce_to_pathname
      option :auto_open, BOOLEAN, 'false', 'Whether to automatically open the generated workspaces', nil, nil, coerce_to_bool
      option :clean, BOOLEAN, 'false', 'Whether to clean the generated directories before generating', nil, nil, coerce_to_bool

      option :app_host_source_dir, [String, Pathname], 'nil',
             'A directory containing sources to use for the app host',
             'DIR',
             ->(dir) { 'not a directory' unless dir.directory? },
             coerce_to_pathname

      option :podspec_paths, ArrayOf.new(String, Pathname, URI),
             '[Pathname(?.)]',
             nil,
             nil,
             ->(paths) { ('paths do not exist' unless paths.all? { |p| p.is_a?(URI) || p.exist? }) },
             ->(paths) { paths && paths.map { |path| path.to_s =~ %r{https?://} ? URI(path) : Pathname(path).expand_path } }
      option :podspecs, ArrayOf.new(Pod::Specification),
             'self.class.podspecs_from_paths(podspec_paths)',
             nil,
             nil,
             ->(specs) { 'no podspecs found' if specs.empty? },
             ->(paths) { paths && paths.map { |path| Pathname(path).expand_path } }

      # installer options
      option :sources, ArrayOf.new(String),
             'if use_podfile && podfile then ::Pod::Installer::Analyzer.new(:sandbox, podfile).sources.map(&:url) else pod_config.sources_manager.all.map(&:url) end',
             'The sources from which to pull dependent pods (defaults to all repos in the podfile if using the podfile, else all available repos). Can be a repo name or URL. Multiple sources must be comma-delimited.',
             'SOURCE1,SOURCE2',
             ->(_) { nil },
             ->(sources) { Array(sources).flat_map { |s| s.split(',') } }
      option :local_sources, ArrayOf.new(String),
             [],
             'Paths from which to find local podspecs for transitive dependencies. Multiple local-sources must be comma-delimited.',
             'SOURCE1,SOURCE2',
             ->(_) { nil },
             ->(local_sources) { Array(local_sources).flat_map { |s| s.split(',') } }
      option :platforms, ArrayOf.new(String),
             nil,
             'Limit to specific platforms. Default is all platforms supported by the podspec. Multiple platforms must be comma-delimited.',
             'ios,macos',
             lambda { |platforms|
               valid_platforms = Platform.all.map { |p| p.string_name.downcase }
               valid_platforms unless (platforms - valid_platforms).empty?
             }, # validates platforms is a subset of Platform.all
             ->(platforms) { Array(platforms).flat_map { |s| s.split(',') } }
      option :repo_update, BOOLEAN, 'false', 'Force running `pod repo update` before install', nil, nil, coerce_to_bool
      option :use_default_plugins, BOOLEAN, 'false', 'Whether installation should activate default plugins', nil, nil, coerce_to_bool
      option :deterministic_uuids, BOOLEAN, '(use_podfile && podfile) ? podfile.installation_options.deterministic_uuids : false', 'Whether installation should use deterministic UUIDs for pods projects', nil, nil, coerce_to_bool
      option :disable_input_output_paths, BOOLEAN, '(use_podfile && podfile) ? podfile.installation_options.disable_input_output_paths : false', 'Whether to disable the input & output paths of the CocoaPods script phases (Copy Frameworks & Copy Resources)', nil, nil, coerce_to_bool
      option :share_schemes_for_development_pods, [TrueClass, FalseClass, Array], '(use_podfile && podfile) ? podfile.installation_options.share_schemes_for_development_pods : true', 'Whether installation should share schemes for development pods', nil, nil
      option :warn_for_multiple_pod_sources, BOOLEAN, '(use_podfile && podfile) ? podfile.installation_options.warn_for_multiple_pod_sources : false', 'Whether installation should warn when a pod is found in multiple sources', nil, nil, coerce_to_bool
      option :use_modular_headers, BOOLEAN, 'false', 'Whether the target should be generated as a clang module, treating dependencies as modules, as if `use_modular_headers!` were specified. Will error if both this option and a podfile are specified', nil, nil, coerce_to_bool

      options.freeze
      options.each do |o|
        attr_reader o.name
        alias_method :"#{o.name}?", o.name if o.type == BOOLEAN
      end

      module_eval <<-RUBY, __FILE__, __LINE__ + 1
            # @!visibility private
            def initialize(
              #{options.map { |o| "#{o.name}: (begin (#{o.default}); rescue => e; e; end)" }.join(', ')}
              )
                #{options.map { |o| "@#{o.name} = #{o.name}" }.join('; ')}
            end
      RUBY

      # @return [Hash<Symbol,Object>] the configuration hash parsed from the given file
      #
      # @param  [Pathname] path
      #
      # @raises [Informative] if the file does not exist or is not a YAML hash
      #
      def self.from_file(path)
        raise Informative, "No cocoapods-generate configuration found at #{UI.path path}" unless path.file?
        require 'yaml'
        yaml = YAML.load_file(path)
        unless yaml.is_a?(Hash)
          unless path.read.strip.empty?
            raise Informative, "Hash not found in configuration at #{UI.path path} -- got #{yaml.inspect}"
          end
          yaml = {}
        end
        yaml = yaml.with_indifferent_access

        Dir.chdir(path.dirname) do
          options.each_with_object({}) do |option, config|
            next unless yaml.key?(option.name)
            config[option.name] = option.coerce yaml[option.name]
          end
        end
      end

      # @return [Hash<Symbol,Object>] the configuration hash parsed from the env
      #
      # @param  [ENV,Hash<String,String>] env
      #
      def self.from_env(env = ENV)
        options.each_with_object({}) do |option, config|
          next unless (value = env["COCOAPODS_GENERATE_#{option.name.upcase}"])
          config[option.name] = option.coerce(value)
        end
      end

      # @return [Array<String>] errors in the configuration
      #
      def validate
        hash = to_h
        self.class.options.map do |option|
          option.validate(hash[option.name])
        end.compact
      end

      # @return [Configuration] a new configuration object with the given changes applies
      #
      # @param  [Hash<Symbol,Object>] changes
      #
      def with_changes(changes)
        self.class.new(**to_h.merge(changes))
      end

      # @return [Hash<Symbol,Object>]
      #         a hash where the keys are option names and values are the non-nil set values
      #
      def to_h
        self.class.options.each_with_object({}) do |option, hash|
          value = send(option.name)
          next if value.nil?
          hash[option.name] = value
        end
      end

      # @return [Boolean] whether this configuration is equivalent to other
      #
      def ==(other)
        self.class == other.class &&
          to_h == other.to_h
      end

      # @return [String] a string describing the configuration, suitable for UI presentation
      #
      def to_s
        hash = to_h
        hash.delete(:pod_config)
        hash.each_with_index.each_with_object('`pod gen` configuration {'.dup) do |((k, v), i), s|
          s << ',' unless i.zero?
          s << "\n" << '  ' << k.to_s << ': ' << v.to_s.gsub(/:0x\h+/, '')
        end << ' }'
      end

      # @return [Pathname] the directory for installation of the generated workspace
      #
      # @param  [String] name the name of the pod
      #
      def gen_dir_for_pod(name)
        gen_directory.join(name)
      end

      # @return [Boolean] whether gen should install with dynamic frameworks
      #
      def use_frameworks?
        !use_libraries?
      end

      # @return [String] The project name to use for generating this workspace.
      #
      # @param [Specification] spec
      #        the specification to generate project name for.
      #
      def project_name_for_spec(spec)
        project_name = spec.name.dup
        # When using multiple Xcode project the project name will collide with the actual .xcodeproj meant for the pod
        # that we are generating the workspace for.
        project_name << 'Sample' if generate_multiple_pod_projects?
        project_name
      end

      # @return [Array<Specification>] the podspecs found at the given paths.
      #         This method will download specs from URLs and traverse a directory's children.
      #
      # @param  [Array<Pathname,URI>] paths
      #         the paths to search for podspecs
      #
      def self.podspecs_from_paths(paths)
        paths = [Pathname('.')] if paths.empty?
        paths.flat_map do |path|
          if path.is_a?(URI)
            require 'cocoapods/open-uri'
            begin
              contents = open(path.to_s).read
            rescue StandardError => e
              next e
            end
            begin
                Pod::Specification.from_string contents, path.to_s
              rescue StandardError
                $ERROR_INFO
              end
          elsif path.directory?
            glob = Pathname.glob(path + '*.podspec{.json,}')
            next StandardError.new "no specs found in #{UI.path path}" if glob.empty?
            glob.map { |f| Pod::Specification.from_file(f) }.sort_by(&:name)
          else
            Pod::Specification.from_file(path)
          end
        end
      end
    end
  end
end
