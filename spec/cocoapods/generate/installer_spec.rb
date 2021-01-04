# frozen_string_literal: true

RSpec.describe Pod::Generate::Installer do
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

  describe_method 'create_app_project' do
    before do
      podfile.defined_in_file = config.gen_dir_for_specs(podspecs).join('Podfile.yaml')
    end

    after do
      FileUtils.rm_rf gen_directory
    end

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
end
