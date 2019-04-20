# `cocoapods-generate`

A [CocoaPods](https://cocoapods.org/) plugin that allows you to easily generate a workspace from a podspec.

Whether you want to completely remove all Xcode projects from your library's repository or you want to be able to focus on a small piece of a monorepo, a single `pod gen` command will build up a workspace suitable for writing, running, testing, and debugging in Xcode.

When you're done working, you don't have to do anything -- and that means no merge conflicts, no managing Xcode projects, and no tearing down a sample app setup. `pod gen` manages all that for you.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cocoapods-generate'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cocoapods-generate

## CLI

The main point of interaction with the plugin is via the `pod gen` command.
It takes in a list of podspecs (or directories) as arguments,
as well as many options that modify how `gen` will create your workspace.

<!-- begin cli usage -->
```
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
    --local-sources=SOURCE1,SOURCE2        Paths from which to find local podspecs.
                                           Multiple local-sources must be
                                           comma-delimited.
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
```
<!-- end cli usage -->

## `.gen_config.yml`

All of the command line options above can also be specified in a `.gen_config.yml` file.

For example, the equivalent of running `pod gen --no-deterministic-uuids --sources=a,b --gen-directory=/tmp/gen --use-libraries` would be

```yaml
deterministic_uuids: false
sources:
- a
- b
gen_directory: /tmp/gen
use_libraries: true
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/rake spec` to run the tests.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `VERSION`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/square/cocoapods-generate. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Code of Conduct

Everyone interacting in the cocoapods-generate project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/square/cocoapods-generate/blob/master/CODE_OF_CONDUCT.md).
