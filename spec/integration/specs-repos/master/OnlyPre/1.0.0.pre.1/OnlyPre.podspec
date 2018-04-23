# frozen_string_literal: true

Pod::Spec.new do |s|
  s.name = 'OnlyPre'
  s.version = '1.0.0.pre.1'

  s.source = { http: "file://#{File.expand_path '../../../../pod.tar', __dir__}" }
end
