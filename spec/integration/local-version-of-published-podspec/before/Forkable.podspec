# frozen_string_literal: true

Pod::Specification.new do |s|
  s.name = 'Forkable'
  s.version = '9.0.0'

  s.authors = %w[Square]
  s.homepage = 'https://github.com/Square/cocoapods-generate'
  s.source = { git: 'https://github.com/Square/cocoapods-generate' }
  s.summary = 'Testing pod'

  s.ios.deployment_target = '9.0'
  s.macos.deployment_target = '10.10'
  s.watchos.deployment_target = '4.0'
  s.tvos.deployment_target = '11.0'

  s.source_files = 'Forkable/Sources'

  s.test_spec 'Tests' do |ts|
    ts.source_files = 'Forkable/Tests'
  end
end
