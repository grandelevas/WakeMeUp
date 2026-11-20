#!/usr/bin/env ruby
# frozen_string_literal: true

# Selection rules for TestFlight external groups. No network and no fastlane.
# Run with: ruby scripts/external-beta-groups.test.rb

require_relative "../fastlane/external_beta_groups"

Group = Struct.new(:name, :is_internal_group)

def check(label)
  yield
  puts "ok #{label}"
rescue StandardError => error
  warn "FAIL #{label}: #{error.message}"
  exit 1
end

check "distributes to every external group and skips internal ones" do
  result = external_beta_group_names([
    Group.new("Test 1", false),
    Group.new("Testing", false),
    Group.new("Testerzy", true),
    Group.new("App Store Connect Users", "true")
  ])
  raise result.inspect unless result[:external] == ["Test 1", "Testing"]
  raise result.inspect unless result[:found] == ["Test 1", "Testing", "Testerzy", "App Store Connect Users"]
end

check "treats the string false as external" do
  result = external_beta_group_names([Group.new("Testing", "false")])
  raise result.inspect unless result[:external] == ["Testing"]
end

check "lists found groups when none are external" do
  result = external_beta_group_names([
    Group.new("Test 1", true),
    Group.new("Testing", true)
  ])
  raise "expected no external groups" unless result[:external].empty?
  raise result.inspect unless result[:found] == ["Test 1", "Testing"]
end

check "reads hash groups" do
  result = external_beta_group_names([{ "name" => "Friends", "is_internal_group" => false }])
  raise result.inspect unless result[:external] == ["Friends"]
end

puts "external beta group selection ok"
