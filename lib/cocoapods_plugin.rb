# frozen_string_literal: true

if Gem::Version.new(Pod::VERSION) >= Gem::Version.new('1.5.0')
  require 'cocoapods/command/gen'
else
  Pod::UI.warn 'cocoapods-generate requires CocoaPods >= 1.5.0'
end
