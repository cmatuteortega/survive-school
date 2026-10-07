#!/usr/bin/env ruby
# Turns LÖVE's own Xcode project (platform/xcode/love.xcodeproj in a love
# checkout) into Survive School's, for the love-ios target only:
#
#   ruby ios/configure.rb <love.xcodeproj> <game.love> <LoveIap.swift>
#
# with the app's identity in the environment (APP_ID, APP_NAME, VERSION_NAME,
# VERSION_CODE) and, for a signed build, IOS_TEAM_ID and IOS_PROFILE_NAME.
#
# Edited through the xcodeproj gem (the library CocoaPods writes projects
# with) rather than by sed: a project file names everything by generated ids,
# and a hand-edit that gets one wrong opens in Xcode as nothing at all.
#
# 1. game.love goes into the app's Resources. LÖVE on iOS looks for a .love
#    in its own bundle first (src/common/ios.mm) and runs it without showing
#    its game picker -- the iOS form of the Android build's embed flavour.
# 2. love-iap's StoreKit bridge (LoveIap.swift) is compiled into the app, with
#    the two settings its README asks for so that iap.lua's ffi.C finds the six
#    liap_* functions in a stripped Release binary, and iOS 15 for StoreKit 2.
# 3. Identity, versions and the icon set ios/appicon.py writes.
# 4. Signing, only when a team is given: manual, with the one provisioning
#    profile the workflow installed. Set on this target and no other, because
#    xcodebuild's command-line settings reach every target, and the static
#    liblove-ios it builds first refuses a provisioning profile outright.

require "xcodeproj"

project_path, game_love, swift_file = ARGV
abort "usage: configure.rb <love.xcodeproj> <game.love> <LoveIap.swift>" unless swift_file
[game_love, swift_file].each { |f| abort "configure: #{f} not found" unless File.file?(f) }

def env!(name)
  ENV.fetch(name) { abort "configure: #{name} is not set" }
end

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == "love-ios" }
abort "configure: no love-ios target in #{project_path}" unless target

group = project.main_group.find_subpath("Survive School", true)
group.set_source_tree("<group>")

# 1. The game
love_ref = group.new_reference(File.expand_path(game_love))
target.resources_build_phase.add_file_reference(love_ref, true)

# 2. The store
swift_ref = group.new_reference(File.expand_path(swift_file))
target.source_build_phase.add_file_reference(swift_ref, true)

team = ENV["IOS_TEAM_ID"].to_s
profile = ENV["IOS_PROFILE_NAME"].to_s

target.build_configurations.each do |config|
  s = config.build_settings

  # 3. Identity. PRODUCT_NAME is the executable and the .app's name, so it
  # stays one word; the home screen shows CFBundleDisplayName (the workflow
  # sets it in the Info.plist).
  s["PRODUCT_BUNDLE_IDENTIFIER"] = env!("APP_ID")
  s["PRODUCT_NAME"] = "SurviveSchool"
  s["MARKETING_VERSION"] = env!("VERSION_NAME")
  s["CURRENT_PROJECT_VERSION"] = env!("VERSION_CODE")
  s["ASSETCATALOG_COMPILER_APPICON_NAME"] = "iOS AppIcon"

  # 2. love-iap's README, step 3 and 4. Swift 5 language mode: the bridge
  # was written before Swift 6's strict concurrency checking.
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  s["SWIFT_VERSION"] = "5.0"
  s["STRIP_STYLE"] = "non-global"
  flags = Array(s["OTHER_LDFLAGS"] || "$(inherited)")
  s["OTHER_LDFLAGS"] = flags | ["-Wl,-export_dynamic"]

  # 4. Signing
  next if team.empty?
  s["DEVELOPMENT_TEAM"] = team
  s["CODE_SIGN_STYLE"] = "Manual"
  s["CODE_SIGN_IDENTITY"] = "Apple Distribution"
  s["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = "Apple Distribution"
  s["PROVISIONING_PROFILE_SPECIFIER"] = profile
  s.delete("PROVISIONING_PROFILE")
end

project.save
puts "configure: love-ios is #{ENV["APP_ID"]} #{ENV["VERSION_NAME"]} (#{ENV["VERSION_CODE"]})" \
     "#{team.empty? ? ", unsigned" : ", team #{team}"}"
