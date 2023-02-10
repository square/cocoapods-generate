module Pod
  module Generate
    # Responsible for creating a workspace for a single specification,
    # given a configuration and a generated podfile.
    #
    class Installer
      DEFAULT_XCODE_VERSION = '9.3'.freeze

      XCODE_VERSION_TO_OBJECT_VERSION = {
        '14.0' => 56,
        '13.0' => 55,
        '12.0' => 54,
        '11.4' => 53,
        '11.0' => 52,
        '10.0' => 51,
        '9.3' => 50,
        '8.0' => 48,
        '6.3' => 47,
        '3.2' => 46,
        '3.1' => 45
      }.freeze

      # @return [Configuration]
      #         the configuration to use when installing
      #
      attr_reader :configuration

      # @return [Array<Specification>]
      #         the spec whose workspace is being created
      #
      attr_reader :specs

      # @return [Podfile]
      #         the podfile to install
      #
      attr_reader :podfile

      def initialize(configuration, specs, podfile)
        @configuration = configuration
        @specs = specs
        @podfile = podfile
      end

      # @return [Pathname]
      #         The directory that pods will be installed into
      #
      def install_directory
        @install_directory ||= podfile.defined_in_file.dirname
      end

      # Installs the {podfile} into the {install_directory}
      #
      # @return [void]
      #
      def install!
        UI.title "Generating workspace in #{UI.path install_directory}" do
          clean! if configuration.clean?
          install_directory.mkpath

          UI.message 'Creating stub application' do
            create_app_project
          end

          UI.message 'Writing Podfile' do
            podfile.defined_in_file.open('w') { |f| f << podfile.to_yaml }
          end

          installer = nil
          UI.section 'Installing...' do
            configuration.pod_config.with_changes(installation_root: install_directory, podfile: podfile,
                                                  lockfile: configuration.lockfile, sandbox: nil,
                                                  sandbox_root: install_directory + 'Pods',
                                                  podfile_path: podfile.defined_in_file,
                                                  silent: !configuration.pod_config.verbose?, verbose: false,
                                                  lockfile_path: nil) do
              installer = ::Pod::Installer.new(configuration.pod_config.sandbox, podfile, configuration.lockfile)
              installer.use_default_plugins = configuration.use_default_plugins
              installer.install!
            end
          end

          UI.section 'Performing post-installation steps' do
            should_perform_post_install = if installer.respond_to?(:generated_aggregate_targets) # CocoaPods 1.7.0
                                            !installer.generated_aggregate_targets.empty?
                                          else
                                            true
                                          end
            perform_post_install_steps(open_app_project, installer) if should_perform_post_install
          end

          print_post_install_message
        end
      end

      private

      # Removes the {install_directory}
      #
      # @return [void]
      #
      def clean!
        UI.message 'Cleaning gen install directory' do
          FileUtils.rm_rf install_directory
        end
      end

      def open_app_project(recreate: false)
        app_project_path = install_directory.join("#{configuration.project_name_for_specs(specs)}.xcodeproj")
        if !recreate && app_project_path.exist?
          Xcodeproj::Project.open(app_project_path)
        else
          version_key = XCODE_VERSION_TO_OBJECT_VERSION.keys.find do |k|
            configuration.xcode_version >= Pod::Version.new(k)
          end || DEFAULT_XCODE_VERSION
          object_version = XCODE_VERSION_TO_OBJECT_VERSION[version_key]
          Xcodeproj::Project.new(app_project_path, false, object_version)
        end
      end

      # Creates an app project that CocoaPods will integrate into
      #
      # @return [Xcodeproj::Project]
      #
      def create_app_project
        app_project = open_app_project(recreate: !configuration.incremental_installation?)

        platforms_by_spec = Hash[specs.map do |spec|
          platforms = spec.available_platforms.flatten.reject do |platform|
            !configuration.platforms.nil? && !configuration.platforms.include?(platform.string_name.downcase)
          end
          [spec, platforms]
        end]

        if platforms_by_spec.values.all?(&:empty?)
          Pod::Command::Gen.help! Pod::StandardError.new "No available platforms for podspecs #{specs.map(&:name).to_sentence} match requested platforms: #{configuration.platforms}"
        end

        platforms_by_spec
          .flat_map do |spec, platforms|
            platforms.map do |platform|
              consumer = spec.consumer(platform)
              target_name = "App-#{Platform.string_name(consumer.platform_name)}"
              next if app_project.targets.map(&:name).include? target_name
              native_app_target = Pod::Generator::AppTargetHelper.add_app_target(app_project, consumer.platform_name,
                                                                                 deployment_target(consumer), target_name)
              # Temporarily set Swift version to pass validator checks for pods which do not specify Swift version.
              # It will then be re-set again within #perform_post_install_steps.
              Pod::Generator::AppTargetHelper.add_swift_version(native_app_target, Pod::Validator::DEFAULT_SWIFT_VERSION)
              native_app_target
            end
          end
          .compact.uniq.tap do
            app_project.recreate_user_schemes do |scheme, target|
              installation_result = installation_result_from_target(target)
              next unless installation_result
              installation_result.test_native_targets.each do |test_native_target|
                scheme.add_test_target(test_native_target)
              end
            end
          end
          .each do |target|
            Xcodeproj::XCScheme.share_scheme(app_project.path.to_s, target.name) if target
          end
        app_project.save
        app_project
      end

      def deployment_target(consumer)
        deployment_target = consumer.spec.deployment_target(consumer.platform_name)
        if consumer.platform_name == :ios && configuration.use_frameworks?
          minimum = Version.new('8.0')
          deployment_target = [Version.new(deployment_target), minimum].max.to_s
        end
        deployment_target
      end

      def perform_post_install_steps(app_project, installer)
        app_project.native_targets.each do |native_app_target|
          remove_script_phase_from_target(native_app_target, 'Check Pods Manifest.lock')

          spec_names = specs.map(&:name)
          pod_targets = installer.pod_targets.select do |pt|
            pt.platform.name == native_app_target.platform_name && spec_names.include?(pt.pod_name)
          end

          native_app_target.source_build_phase.clear
          native_app_target.resources_build_phase.clear

          if (app_host_source_dir = configuration.app_host_source_dir)
            relative_app_host_source_dir = app_host_source_dir.relative_path_from(install_directory)
            groups = {}

            app_host_source_dir.find do |file|
              relative_path = file.relative_path_from(app_host_source_dir)

              if file.directory?
                groups[relative_path] =
                  if (base_group = groups[relative_path.dirname])
                    basename = relative_path.basename
                    base_group.new_group(basename.to_s, basename)
                  else
                    app_project.new_group(native_app_target.name, relative_app_host_source_dir)
                  end

                next
              elsif file.to_s.end_with?('-Bridging-Header.h')
                native_app_target.build_configurations.each do |bc|
                  if (old_bridging_header = bc.build_settings['SWIFT_OBJC_BRIDGING_HEADER'])
                    raise Informative, "Conflicting Swift ObjC bridging headers specified, got #{old_bridging_header} and #{relative_path}. Only one `-Bridging-Header.h` file may be specified in the app host source dir."
                  end

                  bc.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = relative_path.to_s
                end
              end

              group = groups[relative_path.dirname]
              source_file_ref = group.new_file(file.basename)
              native_app_target.add_file_references([source_file_ref])
            end
          else
            platform_name = Platform.string_name(native_app_target.platform_name)
            group = group_for_platform_name(app_project, platform_name)
            main_file_ref = group.files.find { |f| f.display_name == 'main.m' }
            if main_file_ref.nil?
              source_file = create_main_source_file(app_project, pod_targets, native_app_target.name)
              group = app_project[group.name] || app_project.new_group(group.name, group.name)
              source_file_ref = group.new_file(source_file)
              native_app_target.add_file_references([source_file_ref])
            else
              native_app_target.add_file_references([main_file_ref])
            end
          end

          # Set `PRODUCT_BUNDLE_IDENTIFIER`
          native_app_target.build_configurations.each do |bc|
            bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.cocoapods-generate.${PRODUCT_NAME:rfc1034identifier}'
          end

          case native_app_target.platform_name.to_sym
          when :ios
            make_ios_app_launchable(app_project, native_app_target)
          when :osx
            generate_infoplist_file(app_project, native_app_target)
          when :tvos
            generate_infoplist_file(app_project, native_app_target)
          end

          swift_version = pod_targets.map { |pt| Pod::Version.new(pt.swift_version) }.max.to_s

          Pod::Generator::AppTargetHelper.add_swift_version(native_app_target, swift_version) unless swift_version.blank?
          if installer.pod_targets.any? { |pt| pt.spec_consumers.any? { |c| c.frameworks.include?('XCTest') } }
            Pod::Generator::AppTargetHelper.add_xctest_search_paths(native_app_target)
          end

          pod_targets.each do |pod_target|
            result = installer.target_installation_results.pod_target_installation_results[pod_target.name]
            next unless result
            share_scheme(result.native_target.project, pod_target.label)
            pod_target.test_specs.each do |test_spec|
              share_scheme(result.native_target.project, pod_target.test_target_label(test_spec))
            end
            pod_target.app_specs.each do |app_spec|
              share_scheme(result.native_target.project, pod_target.app_target_label(app_spec))
            end
          end

          add_test_spec_schemes_to_app_scheme(installer, app_project)
        end

        app_project.save
      end

      def installation_result_from_target(target)
        return unless target.respond_to?(:symbol_type)
        library_product_types = %i[framework dynamic_library static_library]
        return unless library_product_types.include? target.symbol_type

        results_by_native_target[target]
      end

      def remove_script_phase_from_target(native_target, script_phase_name)
        script_phase = native_target.shell_script_build_phases.find { |bp| bp.name && bp.name.end_with?(script_phase_name) }
        return unless script_phase.present?
        native_target.build_phases.delete(script_phase)
      end

      def add_test_spec_schemes_to_app_scheme(installer, app_project)
        spec_root_names = Set.new(specs.map { |s| s.root.name })

        test_native_targets =
          installer
          .target_installation_results
          .pod_target_installation_results
          .values
          .flatten(1)
          .select { |installation_result| spec_root_names.include?(installation_result.target.pod_name) }
          .flat_map(&:test_native_targets)
          .group_by(&:platform_name)

        workspace_path = install_directory + (configuration.project_name_for_specs(specs) + '.xcworkspace')
        Xcodeproj::Plist.write_to_path(
          { 'IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded' => false },
          workspace_path.join('xcshareddata').tap(&:mkpath).join('WorkspaceSettings.xcsettings')
        )

        test_native_targets.each do |platform_name, test_targets|
          app_scheme_path = Xcodeproj::XCScheme.shared_data_dir(app_project.path).join("App-#{Platform.string_name(platform_name)}.xcscheme")
          raise "Missing app scheme for #{platform_name}: #{app_scheme_path.inspect}" unless app_scheme_path.file?

          app_scheme = Xcodeproj::XCScheme.new(app_scheme_path)
          test_action = app_scheme.test_action
          existing_test_targets = test_action.testables.flat_map(&:buildable_references).map(&:target_name)

          test_targets.sort_by(&:name).each do |target|
            next if existing_test_targets.include?(target.name)

            testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(target)
            testable.buildable_references.each do |buildable|
              buildable.xml_element.attributes['ReferencedContainer'] = "container:Pods/#{File.basename(target.project.path)}"
            end
            test_action.add_testable(testable)
          end

          app_scheme.save!
        end
      end

      def make_ios_app_launchable(app_project, native_app_target)
        platform_name = Platform.string_name(native_app_target.platform_name)
        generated_source_dir = install_directory.join("App-#{platform_name}").tap(&:mkpath)

        # Add `LaunchScreen.storyboard`
        launch_storyboard = generated_source_dir.join('LaunchScreen.storyboard')
        launch_storyboard.write <<-XML.strip_heredoc
              <?xml version="1.0" encoding="UTF-8" standalone="no"?>
              <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="13122.16" systemVersion="17A277" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
                <dependencies>
                  <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="13104.12"/>
                  <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
                </dependencies>
                <scenes>
                  <!--View Controller-->
                  <scene sceneID="EHf-IW-A2E">
                    <objects>
                      <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                        <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                          <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
                          <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                          <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        </view>
                      </viewController>
                      <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
                    </objects>
                    <point key="canvasLocation" x="53" y="375"/>
                  </scene>
                </scenes>
              </document>
            XML

        # Add & wire `Info.plist`
        info_plist_contents = {
          'CFBundleDevelopmentRegion' => '$(DEVELOPMENT_LANGUAGE)',
          'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
          'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
          'CFBundleInfoDictionaryVersion' => '6.0',
          'CFBundleName' => '$(PRODUCT_NAME)',
          'CFBundlePackageType' => 'APPL',
          'CFBundleShortVersionString' => '1.0',
          'CFBundleVersion' => '1',
          'LSRequiresIPhoneOS' => true,
          'UILaunchStoryboardName' => 'LaunchScreen',
          'UIRequiredDeviceCapabilities' => [
            'armv7'
          ],
          'UISupportedInterfaceOrientations' => %w[
            UIInterfaceOrientationPortrait
            UIInterfaceOrientationLandscapeLeft
            UIInterfaceOrientationLandscapeRight
          ],
          'UISupportedInterfaceOrientations~ipad' => %w[
            UIInterfaceOrientationPortrait
            UIInterfaceOrientationPortraitUpsideDown
            UIInterfaceOrientationLandscapeLeft
            UIInterfaceOrientationLandscapeRight
          ]
        }
        info_plist_path = generated_source_dir.join('Info.plist')
        Xcodeproj::Plist.write_to_path(info_plist_contents, info_plist_path)

        native_app_target.build_configurations.each do |bc|
          bc.build_settings['INFOPLIST_FILE'] = "${SRCROOT}/App-#{platform_name}/Info.plist"
        end

        group = group_for_platform_name(app_project, platform_name)
        group.files.find { |f| f.display_name == 'Info.plist' } || group.new_file(info_plist_path)
        launch_storyboard_file_ref = group.files.find { |f| f.display_name == 'LaunchScreen.storyboard' } || group.new_file(launch_storyboard)
        native_app_target.resources_build_phase.add_file_reference(launch_storyboard_file_ref)
      end

      def generate_infoplist_file(_app_project, native_app_target)
        # Starting in Xcode 14, there is an error when you build the macOS or
        # tvOS app that is generated from cocoapods-generate. This implements
        # the suggested change.
        native_app_target.build_configurations.each do |bc|
          bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
        end
      end

      def group_for_platform_name(project, platform_name, should_create = true)
        project.main_group.find_subpath("App-#{platform_name}", should_create)
      end

      def print_post_install_message
        workspace_path = install_directory.join(podfile.workspace_path)

        if configuration.auto_open?
          configuration.pod_config.with_changes(verbose: true) do
            Executable.execute_command 'open', [workspace_path]
          end
        else
          UI.info "Open #{UI.path workspace_path} to work on it!"
        end
      end

      def share_scheme(project, scheme_name)
        scheme = Xcodeproj::XCScheme.user_data_dir(project.path) + "#{scheme_name}.xcscheme"
        return unless File.exist?(scheme)
        Xcodeproj::XCScheme.share_scheme(project.path, scheme_name)
      end

      def create_main_source_file(project, pod_targets, name)
        source_file = project.path.dirname.+("#{name}/main.m")
        source_file.parent.mkpath

        import_statements = pod_targets.map do |pod_target|
          if pod_target.should_build? && pod_target.defines_module?
            "@import #{pod_target.product_module_name};"
          else
            header_name = "#{pod_target.product_module_name}/#{pod_target.product_module_name}.h"
            "#import <#{header_name}>" if pod_target.sandbox.public_headers.root.+(header_name).file?
          end
        end.compact

        source_file.open('w') do |f|
          f << import_statements.join("\n")
          f << "\n" unless import_statements.empty?
          f << "int main() { return 0; }\n"
        end

        source_file
      end
    end
  end
end
