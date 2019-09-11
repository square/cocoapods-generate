# frozen_string_literal: true

RSpec.describe Pod::Generate::PodfileGenerator do
  let(:podfile) { Pod::Podfile.new {} }
  let(:lockfile_specs) { [] }
  let(:lockfile) { Pod::Lockfile.generate(podfile, lockfile_specs, {}) }
  let(:use_modular_headers) { false }
  let(:config_options) { { podfile: podfile, lockfile: lockfile, use_podfile: !!podfile, use_lockfile_versions: !!lockfile, use_modular_headers: use_modular_headers } }
  let(:config) { Pod::Generate::Configuration.new(**config_options) }

  subject(:podfile_generator) { described_class.new(config) }

  describe_method 'configuration' do
    it { should eq configuration }
  end

  describe_method 'podfile_dependencies' do
    context 'when use_podfile: false' do
      let(:config_options) { { use_podfile: false } }
      it { should be_empty }
    end

    context 'when podfile has no dependencies' do
      let(:podfile) { Pod::Podfile.new }
      it { should be_empty }
    end

    context 'when podfile has dependencies' do
      let(:podfile) do
        Pod::Podfile.new do
          pod 'A', '>= 1'
        end
      end
      it { should eq 'A' => [Pod::Dependency.new('A', '>= 1')] }
    end
  end

  describe_method 'lockfile_versions' do
    context 'when use_lockfile: false' do
      let(:config_options) { super().merge(use_lockfile: false) }
      it { should be_empty }
    end

    context 'when use_lockfile_versions: false' do
      let(:config_options) { super().merge(use_lockfile_versions: false) }
      it { should be_empty }
    end

    context 'when lockfile has no dependencies' do
      it { should be_empty }
    end

    context 'when lockfile has dependencies' do
      let(:podfile) { Pod::Podfile.new { pod 'A', '>= 1' } }
      let(:lockfile_specs) { [Pod::Specification.new(nil, 'A') { |s| s.version = '1' }] }
      it { should eq 'A' => '= 1' }
    end
  end

  describe_method 'podfiles_by_spec' do
    let(:config_options) { { podspecs: [Pod::Spec.new(nil, 'A'), Pod::Spec.new(nil, 'B')] } }
    before do
      expect(podfile_generator).to receive(:podfile_for_spec).twice.and_wrap_original do |_original_method, spec, &_|
        "Podfile for #{spec.name}"
      end
    end

    it { should eq Pod::Spec.new(nil, 'A') => 'Podfile for A', Pod::Spec.new(nil, 'B') => 'Podfile for B' }
  end

  describe_method 'pod_args_for_dependency' do
    let(:lockfile_versions) { { 'A' => '= 1' } }
    let(:podfile_dependencies) { { 'A' => [Pod::Dependency.new('A')] } }

    before do
      allow(podfile_generator).to receive(:lockfile_versions).and_return lockfile_versions
      allow(podfile_generator).to receive(:podfile_dependencies).and_return podfile_dependencies
    end

    let(:dependency) { Pod::Dependency.new('A') }
    let(:podfile) do
      super().tap do |podfile|
        podfile.defined_in_file = Pathname('Podfile').expand_path
        allow(podfile).to receive(:checksum).and_return 'csum'
      end
    end
    let(:method_args) { [podfile, dependency] }

    it { should eq ['A', '>= 0', '= 1'] }

    context 'when the podfile dependency has an external source' do
      let(:podfile_dependencies) { { 'A' => [Pod::Dependency.new('A', git: 'https://github.com/pod.git')] } }

      it { should eq ['A', { git: 'https://github.com/pod.git' }] }
    end

    context 'when the podfile dependency has a source' do
      let(:podfile_dependencies) { { 'A' => [Pod::Dependency.new('A', '< 5', source: 'https://github.com/pod.git')] } }

      it { should eq ['A', '< 5', '= 1', { source: 'https://github.com/pod.git' }] }
    end
  end

  describe_method 'podfile_for_spec' do
    let(:spec) do
      Pod::Spec.new do |s|
        s.name = 'A'
        s.version = '1'

        s.dependency 'B'
        s.dependency 'D'

        s.test_spec 'Tests' do |ts|
          ts.dependency 'C'
        end

        s.defined_in_file = Pathname('Frameworks/A/A.podspec').expand_path
      end
    end
    let(:method_args) { [spec] }

    it { should be_instance_of Pod::Podfile }

    it 'generates the expected podfile' do
      test = self
      expected = Pod::Podfile.new do
        self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

        workspace 'A.xcworkspace'
        project 'A.xcodeproj'

        plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
        plugin 'cocoapods-generate'

        install! 'cocoapods',
                 deterministic_uuids: false,
                 generate_multiple_pod_projects: false,
                 incremental_installation: false,
                 share_schemes_for_development_pods: true,
                 warn_for_multiple_pod_sources: false

        use_frameworks!(false)

        pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

        abstract_target 'Transitive Dependencies' do
        end

        target 'App-iOS'
        target 'App-macOS'
        target 'App-tvOS'
        target 'App-watchOS'
      end

      expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
    end

    context 'when there are transitive dependencies that are in the podfile' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          plugin 'plugin5', foo: { 'bar' => %w[3], 'baz' => %w[1 2] }, qux: '5'
          pod 'A', path: 'Frameworks/A/A.podspec'
          pod 'B', path: 'Frameworks/B/B.podspec'
          pod 'C', path: 'Frameworks/C/C.podspec'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'
          plugin 'plugin5', foo: { 'bar' => %w[3], 'baz' => %w[1 2] }, qux: '5'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
            pod 'B', path: '../../Frameworks/B/B.podspec'
            pod 'C', path: '../../Frameworks/C/C.podspec'
          end

          target 'App-iOS'
          target 'App-macOS'
          target 'App-tvOS'
          target 'App-watchOS'
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when a dependency specifies :modular_headers / :inhibit_warnings' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          plugin 'plugin-used'
          target 'X' do
            pod 'A', path: 'Frameworks/A/A.podspec', modular_headers: true, inhibit_warnings: true
            pod 'B', path: 'Frameworks/B/B.podspec', modular_headers: true, inhibit_warnings: true
          end
          target 'Y'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'
          plugin 'plugin-used'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests], modular_headers: true, inhibit_warnings: true

          abstract_target 'Transitive Dependencies' do
            pod 'B', path: '../../Frameworks/B/B.podspec', modular_headers: true, inhibit_warnings: true
          end

          target 'App-iOS'
          target 'App-macOS'
          target 'App-tvOS'
          target 'App-watchOS'
        end

        expected.target_definitions['Transitive Dependencies'].send(:internal_hash).delete('use_modular_headers')
        expected.target_definitions['Transitive Dependencies'].send(:internal_hash).delete('inhibit_warnings')
        expected.target_definitions['Pods'].send(:internal_hash)['use_modular_headers']['for_pods'] = %w[A A B]
        expected.target_definitions['Pods'].send(:internal_hash)['inhibit_warnings']['for_pods'] = %w[A A B]

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when local-sources are requested' do
      let(:config_options) { super().merge(local_sources: ['./relative', '/absolute']) }
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          plugin 'plugin-used'
          target 'X' do
            pod 'A', path: 'Frameworks/A/A.podspec'
          end
          target 'Y'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        allow(File).to receive(:file?).and_call_original
        allow(File).to receive(:file?).with('./relative/B.podspec') { true }
        allow(File).to receive(:file?).with('/absolute/D.podspec') { true }
        allow(Pod::Specification).to receive(:from_file).and_return(Pod::Specification.new { |s| s.name = 'Dummy' })
        allow(Pod::Specification).to receive(:dependencies).and_return(nil)
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'
          plugin 'plugin-used'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]
          pod 'B', path: '../.././relative/B.podspec'
          pod 'D', path: '/absolute/D.podspec'

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS'
          target 'App-macOS'
          target 'App-tvOS'
          target 'App-watchOS'
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when only ios platform is requested' do
      let(:config_options) { super().merge(platforms: ['ios']) }
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          plugin 'plugin-used'
          target 'X' do
            pod 'A', path: 'Frameworks/A/A.podspec'
          end
          target 'Y'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        allow(File).to receive(:file?).and_call_original
        allow(Pod::Specification).to receive(:from_file).and_return(Pod::Specification.new { |s| s.name = 'Dummy' })
        allow(Pod::Specification).to receive(:dependencies).and_return(nil)
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'
          plugin 'plugin-used'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS'
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when use_modular_headers! and use_podfile is specified' do
      let(:use_modular_headers) { true }

      it 'raises an exception' do
        expect(config_options[:use_podfile]).to eq(true)
        expect { podfile_generator.use_modular_headers? }.to raise_error Pod::Informative, a_string_including('Conflicting `use_modular_headers` option. Cannot specify both `--use-modular-headers` and `--use-podfile`.')
      end
    end

    context 'when use_modular_headers! / inhibit_all_warnings! is specified' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          inhibit_all_warnings!
          use_modular_headers!
          pod 'A', path: 'Frameworks/A/A.podspec', modular_headers: false
          pod 'B', path: 'Frameworks/B/B.podspec', inhibit_warnings: false
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          inhibit_all_warnings!
          use_modular_headers!

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests], modular_headers: false

          abstract_target 'Transitive Dependencies' do
            pod 'B', path: '../../Frameworks/B/B.podspec', inhibit_warnings: false
          end

          target 'App-iOS'
          target 'App-macOS'
          target 'App-tvOS'
          target 'App-watchOS'
        end

        expected.target_definitions['Transitive Dependencies'].send(:internal_hash).delete('inhibit_warnings')
        expected.target_definitions['Pods'].send(:internal_hash)['inhibit_warnings']['not_for_pods'] = %w[B]

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when the podfile specifies a swift version' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          target('A') { current_target_definition.swift_version = '1' }
          target('B') { current_target_definition.swift_version = '2' }
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS' do
            current_target_definition.swift_version = '2'
          end
          target 'App-macOS' do
            current_target_definition.swift_version = '2'
          end
          target 'App-tvOS' do
            current_target_definition.swift_version = '2'
          end
          target 'App-watchOS' do
            current_target_definition.swift_version = '2'
          end
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when the podfile specifies multiple supported swift versions' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          supports_swift_versions ['4.2', '5']
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(false)

          supports_swift_versions ['4.2', '5']

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS' do
          end
          target 'App-macOS' do
          end
          target 'App-tvOS' do
          end
          target 'App-watchOS' do
          end
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when the podfile sets use_frameworks! as a boolean' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          use_frameworks!(true)
          target 'X' do
            pod 'A', path: 'Frameworks/A/A.podspec'
          end
          target 'Y'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(true)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS' do
          end
          target 'App-macOS' do
          end
          target 'App-tvOS' do
          end
          target 'App-watchOS' do
          end
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end

    context 'when the podfile specifies use_frameworks! as a hash' do
      let(:podfile) do
        Pod::Podfile.new do
          self.defined_in_file = Pathname('Podfile').expand_path
          use_frameworks!(linkage: :static)
          target 'X' do
            pod 'A', path: 'Frameworks/A/A.podspec'
          end
          target 'Y'
        end.tap { |pf| allow(pf).to receive(:checksum).and_return 'csum' }
      end

      it 'generates the expected podfile' do
        test = self
        expected = Pod::Podfile.new do
          self.defined_in_file = test.config.gen_dir_for_pod('A').join('Podfile.yaml')

          workspace 'A.xcworkspace'
          project 'A.xcodeproj'

          plugin 'cocoapods-disable-podfile-validations', 'no_abstract_only_pods' => true
          plugin 'cocoapods-generate'

          source 'https://cdn.cocoapods.org/'

          install! 'cocoapods',
                   deterministic_uuids: false,
                   generate_multiple_pod_projects: false,
                   incremental_installation: false,
                   share_schemes_for_development_pods: true,
                   warn_for_multiple_pod_sources: false

          use_frameworks!(linkage: :static)

          pod 'A', path: '../../Frameworks/A/A.podspec', testspecs: %w[Tests]

          abstract_target 'Transitive Dependencies' do
          end

          target 'App-iOS' do
          end
          target 'App-macOS' do
          end
          target 'App-tvOS' do
          end
          target 'App-watchOS' do
          end
        end

        expect(podfile_for_spec.to_yaml).to eq expected.to_yaml
      end
    end
  end
end
