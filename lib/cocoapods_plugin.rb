# frozen_string_literal: true

if Pod::VERSION >= '1.5.0'
  require 'cocoapods/command/gen'
else
  Pod::UI.warn 'cocoapods-generate requires CocoaPods >= 1.5.0'
end
