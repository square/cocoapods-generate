# frozen_string_literal: true

RSpec.describe Pod::Generate::Installer do
  def pod_target_double(name, platform = Pod::Platform.ios, test_specs = [], app_specs = [], swift_version = nil)
    pod_target = double("pod_target_double (#{name})")
    allow(pod_target).to receive(:platform).and_return(platform)
    allow(pod_target).to receive(:name).and_return(name)
    allow(pod_target).to receive(:pod_name).and_return(name)
    allow(pod_target).to receive(:label).and_return(name)
    allow(pod_target).to receive(:spec_consumers).and_return([])
    allow(pod_target).to receive(:product_module_name).and_return(name)
    allow(pod_target).to receive(:should_build?).and_return(true)
    allow(pod_target).to receive(:defines_module?).and_return(true)
    allow(pod_target).to receive(:swift_version).and_return(swift_version)
    allow(pod_target).to receive(:test_specs).and_return(test_specs)
    allow(pod_target).to receive(:app_specs).and_return(app_specs)
    pod_target
  end

  def native_target_double(name, project)
    native_target = double("native_target_double (#{name})")
    allow(native_target).to receive(:project).and_return(project)
    native_target
  end

  let(:podspecs) { [Pod::Spec.new(nil, 'A'), Pod::Spec.new(nil, 'B')] }
  let(:lockfile_specs) { [] }
  let(:gen_directory) { Pathname('./spec/cocoapods/generate/gen') }
  let(:lockfile) { Pod::Lockfile.generate(podfile, lockfile_specs, {}) }
  let(:config_options) do
    { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile,
      use_lockfile_versions: !!lockfile, gen_directory: gen_directory }
  end
  let(:config) { Pod::Generate::Configuration.new(**config_options) }
  let(:podfile) { Pod::Podfile.new {} }

  subject(:installer) { described_class.new(config, podspecs, podfile) }

  it { should_not be_nil }

  before do
    podfile.defined_in_file = config.gen_dir_for_specs(podspecs).join('Podfile.yaml')
  end

  after do
    FileUtils.rm_rf gen_directory
  end

  describe_method 'perform_post_install_steps' do
    let(:app_project) do
      app_project = Xcodeproj::Project.new(Pathname.new(gen_directory + 'AppProject.xcodeproj'))
      app_project.new_target(:application, 'App-iOS', :ios)
      app_project
    end
    let(:pods_project) do
      Xcodeproj::Project.new(Pathname.new(gen_directory + 'Pods/Pods.xcodeproj'))
    end
    let(:pod_target_a) { pod_target_double('A') }
    let(:pod_target_b) { pod_target_double('B') }
    let(:native_target_a) { native_target_double('A', pods_project) }
    let(:native_target_b) { native_target_double('B', pods_project) }
    let(:pod_target_installation_results) do
      pod_target_installation_result_a = Pod::Installer::Xcode::PodsProjectGenerator::TargetInstallationResult.new(pod_target_a, native_target_a)
      pod_target_installation_result_b = Pod::Installer::Xcode::PodsProjectGenerator::TargetInstallationResult.new(pod_target_b, native_target_b)
      { 'A' => pod_target_installation_result_a, 'B' => pod_target_installation_result_b }
    end
    let(:cocoapods_installer) do
      installer = double('cocoapods_installer')
      allow(installer).to receive(:pod_targets).and_return([pod_target_a, pod_target_b])
      allow(installer).to receive(:target_installation_results).and_return(
        Pod::Installer::Xcode::PodsProjectGenerator::InstallationResults.new(pod_target_installation_results)
      )
      installer
    end
    let(:method_args) { [app_project, cocoapods_installer] }

    context 'scheme sharing' do
      it 'shares all schemes if they are present' do
        allow(File).to receive(:exist?).with(Xcodeproj::XCScheme.user_data_dir(pods_project.path) + 'A.xcscheme').and_return(true)
        allow(File).to receive(:exist?).with(Xcodeproj::XCScheme.user_data_dir(pods_project.path) + 'B.xcscheme').and_return(true)
        expect(Xcodeproj::XCScheme).to receive(:share_scheme).with(pods_project.path, 'A')
        expect(Xcodeproj::XCScheme).to receive(:share_scheme).with(pods_project.path, 'B')
        subject
      end

      it 'shares only schemes that exist' do
        allow(File).to receive(:exist?).with(Xcodeproj::XCScheme.user_data_dir(pods_project.path) + 'A.xcscheme').and_return(true)
        allow(File).to receive(:exist?).with(Xcodeproj::XCScheme.user_data_dir(pods_project.path) + 'B.xcscheme').and_return(false)
        expect(Xcodeproj::XCScheme).to receive(:share_scheme).with(pods_project.path, 'A')
        expect(Xcodeproj::XCScheme).to receive(:share_scheme).with(pods_project.path, 'B').never
        subject
      end

      context 'with incremental installation' do
        let(:pod_target_installation_results) do
          pod_target_installation_result_a = Pod::Installer::Xcode::PodsProjectGenerator::TargetInstallationResult.new(pod_target_a, native_target_a)
          { 'A' => pod_target_installation_result_a }
        end
        it 'shares schemes of pod targets that were installed' do
          allow(File).to receive(:exist?).with(Xcodeproj::XCScheme.user_data_dir(pods_project.path) + 'A.xcscheme').and_return(true)
          expect(Xcodeproj::XCScheme).to receive(:share_scheme).with(pods_project.path, 'A')
          subject
        end
      end
    end
  end

  describe_method 'create_app_project' do
    it 'should create all targets across all specs for app project' do
      expect(subject.targets.map(&:name)).to eq(%w[App-macOS App-iOS App-tvOS App-watchOS])
    end

    context 'with different deployment targets in specs' do
      let(:podspecs) do
        [Pod::Spec.new(nil, 'A') { |s| s.ios.deployment_target = '11.0' },
         Pod::Spec.new(nil, 'B') { |s| s.macos.deployment_target = '10.13' }]
      end
      it 'should create correct app project targets' do
        expect(subject.targets.map(&:name)).to eq(%w[App-iOS App-macOS])
      end
    end

    context 'with unsupported platforms for config' do
      let(:config_options) do
        { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile,
          use_lockfile_versions: !!lockfile, gen_directory: gen_directory, platforms: 'ios' }
      end
      let(:podspecs) do
        [Pod::Spec.new(nil, 'A') { |s| s.watchos.deployment_target = '11.0' }]
      end
      it 'should create correct app project targets' do
        expect { subject }.to raise_error do |error|
          expect(error).to be_a(CLAide::Help)
          expect(error.message).to start_with('[!] No available platforms for podspecs A match requested platforms: ios')
        end
      end
    end
  end

  describe_method 'open_app_project' do
    context 'without specifying xcode-version parameter' do
      it 'sets correct default object version' do
        expect(subject.object_version).to eq '50'
      end
    end

    context 'with specifying xcode version parameter' do
      let(:config_options) do
        { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile,
          use_lockfile_versions: !!lockfile, gen_directory: gen_directory, xcode_version: Pod::Version.new('10.0') }
      end
      it 'sets correct object version' do
        expect(subject.object_version).to eq '51'
      end
    end

    context 'with specifying an unknown xcode version parameter' do
      let(:config_options) do
        { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile,
          use_lockfile_versions: !!lockfile, gen_directory: gen_directory, xcode_version: Pod::Version.new('1.0') }
      end
      it 'sets correct object version' do
        expect(subject.object_version).to eq '50'
      end
    end

    context 'with specifying the closest xcode version parameter' do
      let(:config_options) do
        { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile,
          use_lockfile_versions: !!lockfile, gen_directory: gen_directory, xcode_version: Pod::Version.new('10.1') }
      end
      it 'sets correct object version' do
        expect(subject.object_version).to eq '51'
      end
    end
  end
end
