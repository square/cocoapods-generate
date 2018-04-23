# frozen_string_literal: true

Pod::Spec.new do |s|
  s.name = 'A'
  s.version = '1.0.0.LOCAL'

  s.authors = %w[Square]
  s.homepage = 'https://github.com/Square/cocoapods-generate'
  s.source = { git: 'https://github.com/Square/cocoapods-generate' }
  s.summary = 'Testing pod'

  s.source_files = 'Sources/**/*.{h,m,swift}'
  s.private_header_files = 'Sources/Internal/**/*.h'

  s.test_spec 'Tests' do |ts|
    ts.source_files = 'Tests/**/*.{h,m,swift'
  end
end
