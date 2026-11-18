#!/usr/bin/env ruby
# frozen_string_literal: true

# Bootstrap-only: generated the original captAI.xcodeproj from the folder tree.
#
# XCODE NOW OWNS THE PROJECT FILE (docs/DECISIONS.md D-001). Running this script deletes
# captAI.xcodeproj and rebuilds it from scratch, discarding every change made in Xcode
# (signing, capabilities, target membership, build settings). It is kept for reference only
# and refuses to run unless you pass --force.
#
#   ruby scripts/generate_project.rb --force
#
# Requires the `xcodeproj` gem (`gem install xcodeproj`).

require 'xcodeproj'
require 'fileutils'

unless ARGV.include?('--force')
  warn 'Refusing to run: this replaces captAI.xcodeproj and discards changes made in Xcode.'
  warn 'See docs/DECISIONS.md D-001. Pass --force only if you really want to regenerate.'
  exit 1
end

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'captAI.xcodeproj')

APP_NAME = 'captAI'
BUNDLE_ID = 'app.captai.captAI'
DEPLOYMENT_TARGET = '27.0'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastUpgradeCheck'] = '2700'

# --- Configurations and xcconfig ------------------------------------------------------------------
shared_config = project.new_file('Config/Shared.xcconfig')
project.build_configurations.each do |config|
  config.base_configuration_reference = shared_config
  config.build_settings['SDKROOT'] = 'macosx'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = config.name == 'Release' ? 'YES' : 'NO'
  config.build_settings['ONLY_ACTIVE_ARCH'] = config.name == 'Debug' ? 'YES' : 'NO'
  config.build_settings['DEBUG_INFORMATION_FORMAT'] = config.name == 'Debug' ? 'dwarf' : 'dwarf-with-dsym'
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Debug' ? '-Onone' : '-O'
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = config.name == 'Debug' ? 'DEBUG' : ''
  config.build_settings['ENABLE_TESTABILITY'] = config.name == 'Debug' ? 'YES' : 'NO'
end

# --- Helpers ----------------------------------------------------------------------------------------
def add_tree(project, group, dir_on_disk, target, root)
  Dir.children(dir_on_disk).sort.each do |name|
    next if name.start_with?('.')

    path = File.join(dir_on_disk, name)
    if File.directory?(path)
      add_tree(project, group.new_group(name, name), path, target, root)
    elsif name.end_with?('.swift')
      ref = group.new_file(name)
      target.add_file_references([ref])
    end
  end
end

def group_for(project, name, path)
  project.main_group.new_group(name, path)
end

# --- App target -----------------------------------------------------------------------------------
app = project.new_target(:application, APP_NAME, :osx, DEPLOYMENT_TARGET, nil, :swift)
app.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = APP_NAME
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = APP_NAME
  s['INFOPLIST_KEY_LSUIElement'] = 'YES'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  s['INFOPLIST_KEY_NSMicrophoneUsageDescription'] =
    'captAI uses the microphone only if you turn on microphone audio when recording your screen.'
  s['INFOPLIST_KEY_NSHumanReadableCopyright'] = ''
  s['CODE_SIGN_ENTITLEMENTS'] = 'Config/captAI.entitlements'
  s['MARKETING_VERSION'] = '0.1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['COMBINE_HIDPI_IMAGES'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
end

%w[App Features Core].each do |dir|
  full = File.join(ROOT, dir)
  add_tree(project, group_for(project, dir, dir), full, app, ROOT)
end

# Entitlements are referenced by build setting; keep them visible in the navigator too.
config_group = project.main_group['Config'] || project.main_group.new_group('Config', 'Config')
config_group.new_file('captAI.entitlements')
config_group.new_file('Local.xcconfig.example')

# Asset catalog (app icon placeholder and accent colour).
assets_ref = project.main_group.new_group('Resources', 'Resources').new_file('Assets.xcassets')
app.resources_build_phase.add_file_reference(assets_ref)

# --- Test targets ---------------------------------------------------------------------------------
# Unit and integration bundles are NOT hosted by the app. They compile the app's sources (everything except
# the @main entry point) directly into the test module, so tests run without launching the menu-bar app,
# need no window server and cannot touch the user's real settings. Only the UI tests launch the real app.
def add_sources_without_entry_point(project, target)
  %w[App Features Core].each do |dir|
    full = File.join(ROOT, dir)
    add_tree(project, group_for(project, "#{target.name}-#{dir}", dir), full, target, ROOT)
  end
  entry = target.source_build_phase.files.find { |f| f.file_ref&.path == 'CaptAIApp.swift' }
  target.source_build_phase.remove_build_file(entry) if entry
end

def add_test_target(project, app, name, dir, ui: false)
  target = project.new_target(:unit_test_bundle, name, :osx, DEPLOYMENT_TARGET, nil, :swift)
  target.product_type = 'com.apple.product-type.bundle.ui-testing' if ui
  target.add_dependency(app) if ui
  target.build_configurations.each do |config|
    s = config.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.#{name}"
    s['PRODUCT_NAME'] = name
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['SWIFT_STRICT_CONCURRENCY'] = 'complete'
    s['TEST_TARGET_NAME'] = app.name if ui
  end
  group = group_for(project, name, "Tests/#{dir}")
  full = File.join(ROOT, 'Tests', dir)
  add_tree(project, group, full, target, ROOT) if Dir.exist?(full)
  unless ui
    support = group_for(project, "#{name}Support", 'Tests/Support')
    add_tree(project, support, File.join(ROOT, 'Tests', 'Support'), target, ROOT)
    add_sources_without_entry_point(project, target)
  end
  target
end

unit = add_test_target(project, app, 'captAIUnitTests', 'Unit')
integration = add_test_target(project, app, 'captAIIntegrationTests', 'Integration')
ui = add_test_target(project, app, 'captAIUITests', 'UI', ui: true)

project.main_group.new_group('docs', 'docs')
project.main_group.new_group('scripts', 'scripts')

def finalize_target_settings(target)
  # `new_target` seeds target-level defaults that would override Config/Shared.xcconfig; drop the ones we own there.
  target.build_configurations.each do |config|
    config.build_settings.delete('SWIFT_VERSION')
    config.build_settings.delete('MACOSX_DEPLOYMENT_TARGET')
  end
end

finalize_target_settings(app)
finalize_target_settings(unit)
finalize_target_settings(integration)
finalize_target_settings(ui)

project.save

# --- Shared scheme --------------------------------------------------------------------------------
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
[unit, integration, ui].each { |t| scheme.add_test_target(t) }
scheme.set_launch_target(app)
scheme.test_action.build_configuration = 'Debug'
scheme.launch_action.build_configuration = 'Debug'
scheme.save_as(PROJECT_PATH, APP_NAME, true)

puts "Generated #{PROJECT_PATH}"
