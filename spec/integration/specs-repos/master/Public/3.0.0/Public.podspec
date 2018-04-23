# frozen_string_literal: true

Pod::Spec.new do |s|
  s.name = 'Public'
  s.version = '3.0.0'

  s.source = { http: "file://#{File.expand_path '../../../../pod.tar', __dir__}" }
end
