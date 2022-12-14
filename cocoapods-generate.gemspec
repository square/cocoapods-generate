# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-generate'
  spec.version       = File.read(File.expand_path('VERSION', __dir__)).strip
  spec.authors       = ['Samuel Giddins']
  spec.email         = ['segiddins@squareup.com']
  spec.homepage      = 'https://github.com/square/cocoapods-generate'
  spec.license       = 'MIT'

  spec.summary       = 'Generates Xcode workspaces from a podspec.'
  spec.description   = <<-DESCRIPTION.gsub(/^\s*/, '')
    pod gen allows you to keep your Podfile and podspecs as the single source of
    truth for pods under development. By generating throw-away workspaces capable of
    building, running, and testing a pod, you can focus on library development
    without worrying about other code or managing an Xcode project.

    pod gen works particularly well for monorepo projects, since it is capable of
    using your existing settings when generating the workspace, making each gen'ed
    project truly a small slice of the larger application.
  DESCRIPTION

  spec.files         = Dir['*.md', 'lib/**/*', 'VERSION']
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.1'

  spec.add_runtime_dependency 'cocoapods-disable-podfile-validations', '>= 0.1.1', '< 0.3.0'

  spec.add_development_dependency 'bundler', '>= 1.16', '< 3'
  spec.add_development_dependency 'rake', '~> 10.0'
end
