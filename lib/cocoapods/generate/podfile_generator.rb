# frozen_string_literal: true

module Pod
  module Generate
    # Generates podfiles for pod specifications given a configuration.
    #
    class PodfileGenerator
      # @return [Configuration]
      #         the configuration used when generating podfiles
      #
      attr_reader :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      # @return [Hash<Specification, Podfile>]
      #         a hash of specifications to generated podfiles
      #
      def podfiles_by_spec
        Hash[configuration.podspecs.map do |spec|
          [spec, podfile_for_spec(spec)]
        end]
      end

      # @return [Podfile] a podfile suitable for installing the given spec
      #
      # @param  [Specification] spec
      #
      def podfile_for_spec(spec)
        generator = self
        dir = configuration.gen_dir_for_pod(spec.name)

        Pod::Podfile.new do
          project "#{spec.name}.xcodeproj"
          workspace "#{spec.name}.xcworkspace"

          plugin 'cocoapods-generate'

          install! 'cocoapods', generator.installation_options

          generator.podfile_plugins.each do |name, options|
            plugin(*[name, options].compact)
          end

          use_frameworks!(generator.use_frameworks_value)

          if (supported_swift_versions = generator.supported_swift_versions)
            supports_swift_versions(supported_swift_versions)
          end

          # Explicitly set sources
          generator.configuration.sources.each do |source_url|
            source(source_url)
          end

          self.defined_in_file = dir.join('CocoaPods.podfile.yaml')

          test_specs = spec.recursive_subspecs.select(&:test_specification?)
          app_specs = if spec.respond_to?(:app_specification?)
                        spec.recursive_subspecs.select(&:app_specification?)
                      else
                        []
                      end

          # Stick all of the transitive dependencies in an abstract target.
          # This allows us to force CocoaPods to use the versions / sources / external sources
          # that we want.
          # By using an abstract target,
          abstract_target 'Transitive Dependencies' do
            pods_for_transitive_dependencies = [spec.name]
                                               .concat(test_specs.map(&:name))
                                               .concat(test_specs.flat_map { |ts| ts.dependencies.flat_map(&:name) })
                                               .concat(app_specs.map(&:name))
                                               .concat(app_specs.flat_map { |as| as.dependencies.flat_map(&:name) })

            dependencies = generator
                           .transitive_dependencies_by_pod
                           .values_at(*pods_for_transitive_dependencies)
                           .compact
                           .flatten(1)
                           .uniq
                           .sort_by(&:name)
                           .reject { |d| d.root_name == spec.root.name }

            dependencies.each do |dependency|
              pod_args = generator.pod_args_for_dependency(self, dependency)
              pod(*pod_args)
            end
          end

          # Add platform-specific concrete targets that inherit the
          # `pod` declaration for the local pod.
          spec_platform_names = spec.available_platforms.map(&:string_name).flatten.each.reject do |platform_name|
            !generator.configuration.platforms.nil? && !generator.configuration.platforms.include?(platform_name.downcase)
          end

          spec_platform_names.sort.each do |platform_name|
            target "App-#{platform_name}" do
              current_target_definition.swift_version = generator.swift_version if generator.swift_version
            end
          end

          # this block has to come _before_ inhibit_all_warnings! / use_modular_headers!,
          # and the local `pod` declaration
          current_target_definition.instance_exec do
            transitive_dependencies = children.find { |c| c.name == 'Transitive Dependencies' }

            %w[use_modular_headers inhibit_warnings].each do |key|
              value = transitive_dependencies.send(:internal_hash).delete(key)
              next if value.blank?
              set_hash_value(key, value)
            end
          end

          inhibit_all_warnings! if generator.inhibit_all_warnings?
          use_modular_headers! if generator.use_modular_headers?

          # This is the pod declaration for the local pod,
          # it will be inherited by the concrete target definitions below
          pod_options = generator.dependency_compilation_kwargs(spec.name)
          pod_options[:path] = spec.defined_in_file.relative_path_from(dir).to_s
          { testspecs: test_specs, appspecs: app_specs }.each do |key, specs|
            pod_options[key] = specs.map { |s| s.name.sub(%r{^#{Regexp.escape spec.root.name}/}, '') }.sort unless specs.empty?
          end

          pod spec.name, **pod_options

          # Implement local-sources option to set up dependencies to podspecs in the local filesystem.
          next if generator.configuration.local_sources.empty?
          generator.transitive_local_dependencies(spec, generator.configuration.local_sources).sort_by(&:first).each do |dependency, podspec_file|
            pod_options = generator.dependency_compilation_kwargs(dependency.name)
            pod_options[:path] = if podspec_file[0] == '/' # absolute path
                                   podspec_file
                                 else
                                   '../../' + podspec_file
                                 end
            pod dependency.name, **pod_options
          end
        end
      end

      def transitive_local_dependencies(spec, paths, found_podspecs: {}, include_non_library_subspecs: true)
        if include_non_library_subspecs
          non_library_specs = spec.recursive_subspecs.select do |ss|
            ss.test_specification? || (ss.respond_to?(:app_specification?) && ss.app_specification?)
          end
          non_library_specs.each do |subspec|
            transitive_local_dependencies(subspec, paths, found_podspecs: found_podspecs, include_non_library_subspecs: false)
          end
        end
        spec.dependencies.each do |dependency|
          next if found_podspecs.key?(dependency)
          found_podspec_file = nil
          name = dependency.name.split('/')[0]
          paths.each do |path|
            podspec_file = File.join(path, name + '.podspec')
            next unless File.file?(podspec_file)
            found_podspec_file = podspec_file
            break
          end
          next unless found_podspec_file
          found_podspecs[dependency] = found_podspec_file
          transitive_local_dependencies(Pod::Specification.from_file(found_podspec_file), paths, found_podspecs: found_podspecs)
        end
        found_podspecs
      end

      # @return [Boolean]
      #         whether all warnings should be inhibited
      #
      def inhibit_all_warnings?
        return false unless configuration.use_podfile?
        target_definition_list.all? do |target_definition|
          target_definition.send(:inhibit_warnings_hash)['all']
        end
      end

      # @return [Boolean]
      #         whether all pods should use modular headers
      #
      def use_modular_headers?
        if configuration.use_podfile? && configuration.use_modular_headers?
          raise Informative, 'Conflicting `use_modular_headers` option. Cannot specify both `--use-modular-headers` and `--use-podfile`.'
        end

        if configuration.use_podfile?
          target_definition_list.all? do |target_definition|
            target_definition.use_modular_headers_hash['all']
          end
        else
          configuration.use_modular_headers?
        end
      end

      # @return [Boolean, Hash]
      #         the value to use for `use_frameworks!` DSL directive
      #
      def use_frameworks_value
        return configuration.use_frameworks? unless configuration.use_podfile?
        use_framework_values = target_definition_list.map do |target_definition|
          if target_definition.respond_to?(:build_type) # CocoaPods >= 1.9
            build_type = target_definition.build_type
            if build_type.static_library?
              false
            else
              { linkage: build_type == BuildType.dynamic_framework ? :dynamic : :static }
            end
          else
            target_definition.uses_frameworks?
          end
        end.uniq
        raise Informative, 'Multiple use_frameworks! values detected in user Podfile.' unless use_framework_values.count == 1
        use_framework_values.first
      end

      # @return [Hash]
      #         a hash with "compilation"-related dependency options for the `pod` DSL method
      #
      # @param  [String] pod_name
      #
      def dependency_compilation_kwargs(pod_name)
        options = {}
        options[:inhibit_warnings] = inhibit_warnings?(pod_name) if inhibit_warnings?(pod_name) != inhibit_all_warnings?
        options[:modular_headers] = modular_headers?(pod_name) if modular_headers?(pod_name) != use_modular_headers?
        options
      end

      # @return [Hash<String,Array<Dependency>>]
      #         the transitive dependency objects dependency upon by each pod
      #
      def transitive_dependencies_by_pod
        return {} unless configuration.use_lockfile?
        @transitive_dependencies_by_pod ||= begin
          lda = ::Pod::Installer::Analyzer::LockingDependencyAnalyzer
          dependency_graph = Molinillo::DependencyGraph.new
          configuration.lockfile.dependencies.each do |dependency|
            dependency_graph.add_vertex(dependency.name, dependency, true)
          end
          add_to_dependency_graph = if lda.method(:add_to_dependency_graph).parameters.size == 4 # CocoaPods < 1.6.0
                                      ->(pod) { lda.add_to_dependency_graph(pod, [], dependency_graph, []) }
                                    else
                                      ->(pod) { lda.add_to_dependency_graph(pod, [], dependency_graph, [], Set.new) }
                                    end
          configuration.lockfile.internal_data['PODS'].each(&add_to_dependency_graph)

          transitive_dependencies_by_pod = Hash.new { |hash, key| hash[key] = [] }
          dependency_graph.each do |v|
            transitive_dependencies_by_pod[v.name].concat v.recursive_successors.map(&:payload) << v.payload
          end

          transitive_dependencies_by_pod.each_value(&:uniq!)
          transitive_dependencies_by_pod
        end
      end

      # @return [Hash<String,Array<Dependency>>]
      #         dependencies in the podfile grouped by root name
      #
      def podfile_dependencies
        return {} unless configuration.use_podfile?
        @podfile_dependencies ||= configuration.podfile.dependencies.group_by(&:root_name).tap { |h| h.default = [] }
      end

      # @return [Hash<String,String>]
      #         versions in the lockfile keyed by pod name
      #
      def lockfile_versions
        return {} unless configuration.use_lockfile_versions?
        @lockfile_versions ||= Hash[configuration.lockfile.pod_names.map { |name| [name, "= #{configuration.lockfile.version(name)}"] }]
      end

      # @return [Hash<String,Array<Dependency>>]
      #         returns the arguments that should be passed to the Podfile DSL's
      #         `pod` method for the given podfile and dependency
      #
      # @param  [Podfile] podfile
      #
      # @param  [Dependency] dependency
      #
      def pod_args_for_dependency(podfile, dependency)
        dependency = podfile_dependencies[dependency.root_name]
                     .map { |dep| dep.dup.tap { |d| d.name = dependency.name } }
                     .push(dependency)
                     .reduce(&:merge)

        options = dependency_compilation_kwargs(dependency.name)
        options[:source] = dependency.podspec_repo if dependency.podspec_repo
        options.update(dependency.external_source) if dependency.external_source
        %i[path podspec].each do |key|
          next unless (path = options[key])
          options[key] = Pathname(path)
                         .expand_path(configuration.podfile.defined_in_file.dirname)
                         .relative_path_from(podfile.defined_in_file.dirname)
                         .to_s
        end
        args = [dependency.name]
        if dependency.external_source.nil?
          requirements = dependency.requirement.as_list
          if (version = lockfile_versions[dependency.name])
            requirements << version
          end
          args.concat requirements.uniq
        end
        args << options unless options.empty?
        args
      end

      def swift_version
        @swift_version ||= target_definition_list.map(&:swift_version).compact.max
      end

      def supported_swift_versions
        return unless configuration.use_podfile?
        return if target_definition_list.empty?
        return unless target_definition_list.first.respond_to?(:swift_version_requirements)
        target_definition_list.reduce(nil) do |supported_swift_versions, target_definition|
          target_swift_versions = target_definition.swift_version_requirements
          next supported_swift_versions unless target_swift_versions
          Array(target_swift_versions) | Array(supported_swift_versions)
        end
      end

      def installation_options
        installation_options = {
          deterministic_uuids: configuration.deterministic_uuids?,
          share_schemes_for_development_pods: configuration.share_schemes_for_development_pods?,
          warn_for_multiple_pod_sources: configuration.warn_for_multiple_pod_sources?
        }

        if Pod::Installer::InstallationOptions.all_options.include?('generate_multiple_pod_projects')
          installation_options[:generate_multiple_pod_projects] = configuration.generate_multiple_pod_projects?
        end

        if Pod::Installer::InstallationOptions.all_options.include?('incremental_installation')
          installation_options[:incremental_installation] = configuration.incremental_installation?
        end

        installation_options
      end

      def podfile_plugins
        configuration.podfile_plugins.merge('cocoapods-disable-podfile-validations' => { 'no_abstract_only_pods' => true }) do |_key, old_value, new_value|
          old_value.merge(new_value)
        end
      end

      private

      # @return [Array<Podfile::TargetDefinition>]
      #         a list of all target definitions to consider from the podfile
      #
      def target_definition_list
        return [] unless configuration.use_podfile?
        @target_definition_list ||= begin
          list = configuration.podfile.target_definition_list
          list.reject!(&:abstract?) unless list.all?(&:abstract?)
          list
        end
      end

      # @return [Boolean]
      #         whether warnings should be inhibited for the given pod
      #
      # @param  [String] pod_name
      #
      def inhibit_warnings?(pod_name)
        return false unless configuration.use_podfile?
        target_definitions_for_pod(pod_name).all? do |target_definition|
          target_definition.inhibits_warnings_for_pod?(pod_name)
        end
      end

      # @return [Boolean]
      #         whether modular headers should be enabled for the given pod
      #
      # @param  [String] pod_name
      #
      def modular_headers?(pod_name)
        return true if configuration.use_modular_headers?
        return false unless configuration.use_podfile?
        target_definitions_for_pod(pod_name).all? do |target_definition|
          target_definition.build_pod_as_module?(pod_name)
        end
      end

      # @return [Podfile::TargetDefinition]
      #
      # @param  [String] pod_name
      #
      def target_definitions_for_pod(pod_name)
        target_definitions = target_definition_list.reject { |td| td.dependencies.none? { |d| d.name == pod_name } }
        target_definitions.empty? ? target_definition_list : target_definitions
      end
    end
  end
end
