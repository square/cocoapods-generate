# frozen_string_literal: true

RSpec.describe Pod::Generate::Configuration do
  let(:kwargs) { {} }
  subject(:config) { described_class.new(**kwargs) }

  it { should_not be_nil }

  describe_method :to_h do
    it do
      should eq(
        auto_open: false,
        clean: false,
        deterministic_uuids: false,
        gen_directory: Pathname('gen').expand_path,
        podfile_plugins: {},
        pod_config: Pod::Config.instance,
        podspec_paths: [Pathname('.')],
        podspecs: [Pod::StandardError.new('no specs found in `.`')],
        repo_update: false,
        share_schemes_for_development_pods: true,
        sources: %w[https://github.com/CocoaPods/Specs.git https://github.com/Private/SpecsForks.git],
        use_default_plugins: false,
        use_libraries: false,
        use_lockfile_versions: false,
        use_lockfile: false,
        use_modular_headers: false,
        use_podfile: false,
        use_podfile_plugins: false,
        warn_for_multiple_pod_sources: false
      )
    end
  end

  describe_method :to_s do
    it { should eq <<-TO_S.strip_heredoc.chomp }
            `pod gen` configuration {
              use_podfile: false,
              use_podfile_plugins: false,
              podfile_plugins: {},
              use_lockfile: false,
              use_lockfile_versions: false,
              use_libraries: false,
              gen_directory: #{File.expand_path 'gen'},
              auto_open: false,
              clean: false,
              podspec_paths: [#<Pathname:.>],
              podspecs: [#<Pod::StandardError: no specs found in `.`>],
              sources: ["https://github.com/CocoaPods/Specs.git", "https://github.com/Private/SpecsForks.git"],
              repo_update: false,
              use_default_plugins: false,
              deterministic_uuids: false,
              share_schemes_for_development_pods: true,
              warn_for_multiple_pod_sources: false,
              use_modular_headers: false }
        TO_S
  end

  describe_method :validate do
    def should_raise(*args, &blk)
      expect { subject }.to raise_error(*args, &blk)
    end

    let(:podspec_path) { Pathname('A.podspec').expand_path }
    before { podspec_path.write 'Pod::Spec.new' }
    after { FileUtils.rm_f podspec_path }

    context 'with invalid types' do
      let(:kwargs) { { use_podfile_plugins: [] } }

      it { should eq ['[] invalid for use_podfile_plugins, got type Array, expected object of type TrueClass|FalseClass'] }
    end

    context 'with invalid types in an array' do
      let(:kwargs) { { sources: {} } }

      it { should eq ['{} invalid for sources, got type Hash, expected object of type Array<String>'] }
    end

    context 'custom validation errors' do
      let(:kwargs) { { podspecs: [] } }

      it { should eq ['[] invalid for podspecs, no podspecs found'] }
    end

    context 'evaluating a default fails' do
      let(:object) { Object.new }
      let(:kwargs) { { pod_config: object } }

      it {
        should eq [
          "#{object.inspect} invalid for pod_config, got type Object, expected object of type Pod::Config",
          "Error computing podfile_path, undefined method `podfile_path' for #{object.inspect}",
          'Error computing podfile, no implicit conversion of NoMethodError into String',
          "Error computing podfile_plugins, undefined method `plugins' for #<TypeError: no implicit conversion of NoMethodError into String>",
          "Error computing lockfile, undefined method `lockfile' for #{object.inspect}",
          "Error computing sources, undefined method `target_definition_list' for #<TypeError: no implicit conversion of NoMethodError into String>"
        ]
      }
    end
  end

  describe_class_method :from_env do
    let(:env) { {} }
    let(:method_args) { [env] }

    it { should eq({}) }

    context 'with non-option entries' do
      let(:env) do
        {
          'FOO' => 'bar',
          'COCOAPODS_GENERATE' => 'nope',
          'COCOAPODS_GENERATE_' => 'nope',
          'COCOAPODS_GENERATE_UNKNOWN' => 'nope'
        }
      end

      it { should eq({}) }
    end

    context 'with known options' do
      let(:env) do
        {
          'COCOAPODS_GENERATE_SOURCES' => 'a,b,c',
          'COCOAPODS_GENERATE_USE_PODFILE' => 'true',
          'COCOAPODS_GENERATE_USE_LOCKFILE_VERSIONS' => 'false'
        }
      end

      it { should eq(sources: %w[a b c], use_podfile: true, use_lockfile_versions: false) }
    end
  end

  describe_class_method :from_file, :tmpdir do
    let(:file) { Pathname('.gen_config.yml').expand_path }
    let(:yaml) { '' }
    before { file.write(yaml) }

    let(:method_args) { [file] }

    it { should eq({}) }

    context 'with a mix of string/symbol keys' do
      let(:yaml) { "use_podfile: true\n:use_lockfile: false" }

      it { should eq(use_podfile: true, use_lockfile: false) }
    end

    context 'with an unknown key' do
      let(:yaml) { 'UNKNOWN: false' }

      it { should eq({}) }
    end

    context 'should evaluate from the directory of the file' do
      let(:dir) { Pathname('foo').expand_path.tap(&:mkpath) }
      let(:file) { Pathname('.gen_config.yml').expand_path(dir) }
      let(:yaml) { 'podfile_path: abc.rb' }

      it { should eq(podfile_path: dir.join('abc.rb')) }
    end
  end

  describe '#with_changes' do
    it 'returns a new instance' do
      expect(config.with_changes(pod_config: Pod::Config.new)).not_to equal config
    end

    it 'leaves the original instance unchanged' do
      to_h = config.to_h
      config.with_changes(pod_config: Pod::Config.new)
      expect(config.to_h).to eq to_h
    end
  end
end
