# frozen_string_literal: true

RSpec.describe Pod::Command::Gen, :tmpdir do
  describe 'CLAide' do
    it 'registers it self' do
      expect(Pod::Command.parse(%w[gen])).to be_instance_of described_class
    end
  end

  let(:argv) { %w[--no-ansi] }
  subject(:gen) { described_class.parse(argv) }
  let(:run) do
    gen.validate!
    gen.run
    gen
  end

  describe_class_method :summary do
    it { should match(/\A(^.{,80}$\n?)+\z/) }
  end

  describe_class_method :description do
    it { should match(/\A(^.{,80}$\n?)+\z/) }
  end

  describe '--help' do
    let(:argv) { super().concat %w[--help] }

    it 'should print help' do
      expect(lambda do
        expect(-> { run }).to raise_error SystemExit
      end).to output(<<-HELP.strip_heredoc).to_stdout
              Usage:

                  $ pod gen [PODSPEC|DIR ...]

                    Generates Xcode workspaces from a podspec.

                    pod gen allows you to keep your Podfile and podspecs as the single source of
                    truth for pods under development. By generating throw-away workspaces capable of
                    building, running, and testing a pod, you can focus on library development
                    without worrying about other code or managing an Xcode project.

                    pod gen works particularly well for monorepo projects, since it is capable of
                    using your existing settings when generating the workspace, making each gen'ed
                    project truly a small slice of the larger application.

              Options:

                  --silent                               Show nothing
                  --verbose                              Show more debugging information
                  --no-ansi                              Show output without ANSI codes
                  --help                                 Show help banner of specified command
                  --podfile-path=PATH                    Path to podfile to use
                  --use-podfile                          Whether restrictions should be copied from
                                                         the podfile
                  --use-podfile-plugins                  Whether plugins should be copied from the
                                                         podfile
                  --use-lockfile                         Whether the lockfile should be used to
                                                         discover transitive dependencies
                  --use-lockfile-versions                Whether versions from the lockfile should
                                                         be used
                  --use-libraries                        Whether to use libraries instead of
                                                         frameworks
                  --generate-multiple-pod-projects       Whether to generate multiple Xcode projects
                  --incremental-installation             Whether to use incremental installation
                  --gen-directory=PATH                   Path to generate workspaces in
                  --auto-open                            Whether to automatically open the generated
                                                         workspaces
                  --clean                                Whether to clean the generated directories
                                                         before generating
                  --app-host-source-dir=DIR              A directory containing sources to use for
                                                         the app host
                  --sources=SOURCE1,SOURCE2              The sources from which to pull dependent
                                                         pods (defaults to all repos in the podfile
                                                         if using the podfile, else all available
                                                         repos). Can be a repo name or URL. Multiple
                                                         sources must be comma-delimited.
                  --local-sources=SOURCE1,SOURCE2        Paths from which to find local podspecs for
                                                         transitive dependencies. Multiple
                                                         local-sources must be comma-delimited.
                  --repo-update                          Force running `pod repo update` before
                                                         install
                  --use-default-plugins                  Whether installation should activate
                                                         default plugins
                  --deterministic-uuids                  Whether installation should use
                                                         deterministic UUIDs for pods projects
                  --share-schemes-for-development-pods   Whether installation should share schemes
                                                         for development pods
                  --warn-for-multiple-pod-sources        Whether installation should warn when a pod
                                                         is found in multiple sources
                  --use-modular-headers                  Whether the target should be generated as a
                                                         clang module, treating dependencies as
                                                         modules, as if `use_modular_headers!` were
                                                         specified. Will error if both this option
                                                         and a podfile are specified
            HELP
    end
  end

  describe_method :validate! do
    let(:argv) { %w[--podfile-path=./no-such-file .] }

    it { expect { validate! }.to raise_error CLAide::Help, start_with(<<-ERROR.strip_heredoc) }
      [!] #{Pathname('no-such-file').expand_path.inspect} invalid for podfile_path, file does not exist
          Error computing podspecs, no specs found in `.`
    ERROR
  end

  describe_method 'configuration' do
    it { should eq Pod::Generate::Configuration.new(podspec_paths: []) }

    context 'with explicit podspec paths' do
      let(:podspec_paths) { [Pathname('A.podspec'), Pathname('B.podspec')] }
      before do
        podspec_paths.each do |path|
          path.dirname.mkpath
          path.write('Pod::Spec.new')
        end
      end
      let(:argv) { podspec_paths.map(&:to_s) }

      it { should eq Pod::Generate::Configuration.new(podspec_paths: podspec_paths.map(&:expand_path)) }
    end

    context 'with implicit podspec paths' do
      let(:json_path) { Pathname('A.podspec.json') }
      let(:ruby_path) { Pathname('B.podspec') }
      let(:podspec_paths) { [json_path, ruby_path] }

      before do
        json_path.write('{"name":"A"}')
        ruby_path.write('Pod::Spec.new(nil, "B")')
      end

      it { should eq Pod::Generate::Configuration.new(podspec_paths: [], podspecs: podspec_paths.map { |path| Pod::Spec.from_file(path) }) }
    end

    context 'with implicit directory podspec paths' do
      let(:podspec_path) { Pathname('Frameworks/A/A.podspec') }

      before do
        podspec_path.dirname.mkpath
        podspec_path.write('Pod::Spec.new(nil, "A")')
      end

      let(:argv) { [podspec_path.dirname] }

      it { should eq Pod::Generate::Configuration.new(podspec_paths: [podspec_path.dirname.expand_path], podspecs: [Pod::Spec.from_file(podspec_path)]) }
    end

    context 'config options' do
      context 'podfile_path' do
        let(:podfile_path) { Pathname('Nested/Podfile') }
        before do
          podfile_path.dirname.mkpath
          podfile_path.write('# Podfile')
        end
        let(:argv) { %W[--podfile-path=#{podfile_path}] }

        it { should eq Pod::Generate::Configuration.new(podfile_path: podfile_path.expand_path, podspec_paths: []) }
      end

      context 'use_podfile' do
        let(:podfile_path) { Pathname('Podfile') }
        before { podfile_path.write('# Podfile') }
        let(:argv) { %w[--no-use-podfile] }

        it { should eq Pod::Generate::Configuration.new(podfile_path: podfile_path.expand_path, use_podfile: false, podspec_paths: [], podfile: Pod::Podfile.from_file(podfile_path.expand_path)) }
      end

      context 'use_lockfile_versions' do
        let(:podfile_path) { Pathname('Podfile') }
        before { podfile_path.write('# Podfile') }
        let(:lockfile_path) { Pathname('Podfile.lock') }
        before { lockfile_path.write('{}') }
        let(:argv) { %w[--no-use-lockfile-versions] }

        it do
          should eq Pod::Generate::Configuration.new(podfile_path: podfile_path.expand_path,
                                                     podspec_paths: [],
                                                     podfile: Pod::Podfile.from_file(podfile_path.expand_path),
                                                     use_lockfile_versions: false,
                                                     use_lockfile: true,
                                                     lockfile: Pod::Lockfile.from_file(lockfile_path))
        end
      end

      context 'use_lockfile' do
        let(:podfile_path) { Pathname('Podfile').expand_path }
        before { podfile_path.write('# Podfile') }
        let(:lockfile_path) { Pathname('Podfile.lock') }
        before { lockfile_path.write('{}') }
        let(:argv) { %w[--no-use-lockfile] }

        it do
          should eq Pod::Generate::Configuration.new(podfile_path: podfile_path,
                                                     podspec_paths: [],
                                                     podfile: Pod::Podfile.from_file(podfile_path),
                                                     use_lockfile_versions: false,
                                                     use_lockfile: false,
                                                     lockfile: Pod::Lockfile.from_file(lockfile_path))
        end
      end

      context 'use_libraries' do
        let(:argv) { %w[--no-use-libraries] }

        it { should eq Pod::Generate::Configuration.new(use_libraries: false, podspec_paths: []) }
      end

      context 'gen_directory' do
        let(:gen_directory) { Pathname('not_gen') }
        let(:argv) { %W[--gen-directory=#{gen_directory}] }

        it { should eq Pod::Generate::Configuration.new(gen_directory: gen_directory.expand_path, podspec_paths: []) }
      end

      context 'auto_open' do
        let(:argv) { %w[--auto-open] }

        it { should eq Pod::Generate::Configuration.new(auto_open: true, podspec_paths: []) }
      end

      context 'sources' do
        let(:argv) { %w[--sources=a,b,c,d] }

        it { should eq Pod::Generate::Configuration.new(sources: %w[a b c d], podspec_paths: []) }
      end

      context 'merging configurations' do
        let!(:parent_dir) { @parent }
        around do |test|
          @parent = Pathname.pwd
          Dir.chdir Pathname('nested').tap(&:mkpath) do
            test.run
          end
        end

        describe 'when there are multiple configuration files' do
          let(:argv) { %w[--auto-open A.podspec] }
          before do
            Pathname('A.podspec').write('Pod::Spec.new')

            parent_dir.join('Podfile').write 'pod "Podfile"'
            parent_dir.join('Podfile2').write 'pod "Podfile2"'

            parent_config_path = parent_dir.join('.gen_config.yml')
            parent_config = {
              use_libraries: true,
              podfile_path: 'Podfile2',
              use_podfile: false
            }
            parent_config_path.write Pod::YAMLHelper.convert(parent_config)

            local_config_path = Pathname.pwd.join('.gen_config.yml')
            local_config = {
              use_podfile: true,
              clean: false
            }
            local_config_path.write Pod::YAMLHelper.convert(local_config)

            ENV.update(
              'COCOAPODS_GENERATE_NO_SUCH_KEY' => 'dsahjdsha',
              'COCOAPODS_GENERATE_SOURCES' => 'a,b,c',
              'COCOAPODS_GENERATE_USE_LOCKFILE_VERSIONS' => 'false'
            )
          end

          it do
            should eq Pod::Generate::Configuration.new(
              auto_open: true, # CLI
              clean: false, # local
              podfile_path: Pathname('Podfile2').expand_path('..'), # parent, evaluated in that directory
              podspec_paths: [Pathname('A.podspec').expand_path], # CLI args
              sources: %w[a b c], # ENV
              use_libraries: true, # parent
              use_lockfile_versions: false, # ENV
              use_podfile: true, # local, overriding parent
            )
          end
        end
      end

      it 'only loads the Podfile once' do
        Pathname('Podfile').write <<-RUBY
          if defined?(PODFILE_LOAD_COUNT)
            raise "loaded multiple times!"
          else
            PODFILE_LOAD_COUNT = nil
          end
        RUBY

        expect { configuration }.not_to raise_error
      end
    end
  end
end
