#!/usr/bin/env ruby
# frozen_string_literal: true

# TestFlight distribution decisions. No network and no fastlane.
# Run with: ruby scripts/testflight-distribution.test.rb

require_relative "../fastlane/testflight_distribution"

Review = Struct.new(
  :contact_first_name,
  :contact_last_name,
  :contact_phone,
  :contact_email,
  :demo_account_required,
  :demo_account_name,
  :demo_account_password
)
Localization = Struct.new(:description, :feedback_email)

def check(label)
  yield
  puts "ok #{label}"
rescue StandardError => error
  warn "FAIL #{label}: #{error.message}"
  exit 1
end

check "a VALID build is ready and a failed build stops" do
  raise build_processing_decision("VALID").inspect unless build_processing_decision("VALID") == :ready
  raise build_processing_decision("PROCESSING").inspect unless build_processing_decision("PROCESSING") == :wait
  raise build_processing_decision(nil).inspect unless build_processing_decision(nil) == :wait
  raise build_processing_decision("FAILED").inspect unless build_processing_decision("FAILED") == :failed
  raise build_processing_decision("INVALID").inspect unless build_processing_decision("INVALID") == :failed
end

check "names every blank Test Information field" do
  missing = missing_testflight_review_fields(
    Review.new("", nil, "555", "a@b.c", false, nil, nil),
    [Localization.new("  ", "")]
  )
  expected = ["Beta App Description", "Feedback Email", "Contact first name", "Contact last name"]
  raise missing.inspect unless missing == expected
end

check "asks for the demo account only when it is required" do
  review = Review.new("A", "B", "1", "a@b.c", true, "", nil)
  missing = missing_testflight_review_fields(review, [Localization.new("An alarm app.", "a@b.c")])
  raise missing.inspect unless missing == ["Demo account name", "Demo account password"]
end

check "a complete Test Information list is empty" do
  review = Review.new("A", "B", "1", "a@b.c", false, nil, nil)
  missing = missing_testflight_review_fields(review, [Localization.new("An alarm app.", "a@b.c")])
  raise missing.inspect unless missing.empty?
end

check "reads the missing fields out of an App Store Connect error" do
  message = "The provided entity is missing a required attribute - 'contactFirstName' and description"
  named = review_fields_named_in_error(message)
  raise named.inspect unless named.include?("Contact first name")
  raise named.inspect unless named.include?("Beta App Description")
  raise "expected a rejected submission" unless testflight_review_submission_rejected?(message)
end

puts "testflight distribution decisions ok"
