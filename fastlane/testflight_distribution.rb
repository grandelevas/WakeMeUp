# frozen_string_literal: true

# Decisions for TestFlight distribution. No network and no prompts.

def build_processing_decision(state)
  case state.to_s
  when "VALID"
    :ready
  when "FAILED", "INVALID"
    :failed
  else
    :wait
  end
end

def missing_testflight_review_fields(review_detail, localizations)
  missing = []
  missing << "Beta App Description" unless present_on_any?(localizations, :description)
  missing << "Feedback Email" unless present_on_any?(localizations, :feedback_email)
  [
    ["Contact first name", :contact_first_name],
    ["Contact last name", :contact_last_name],
    ["Contact phone", :contact_phone],
    ["Contact email", :contact_email]
  ].each do |label, key|
    missing << label unless field_present?(review_detail, key)
  end
  if boolean_field?(review_detail, :demo_account_required)
    missing << "Demo account name" unless field_present?(review_detail, :demo_account_name)
    missing << "Demo account password" unless field_present?(review_detail, :demo_account_password)
  end
  missing
end

def review_fields_named_in_error(message)
  text = message.to_s
  labels = []
  labels << "Beta App Description" if text.match?(/description/i)
  labels << "Feedback Email" if text.match?(/feedback/i)
  labels << "Contact first name" if text.match?(/first.?name/i)
  labels << "Contact last name" if text.match?(/last.?name/i)
  labels << "Contact phone" if text.match?(/phone/i)
  labels << "Contact email" if text.match?(/contact.?email/i)
  labels << "Demo account name" if text.match?(/demo account name/i)
  labels << "Demo account password" if text.match?(/demo account password/i)
  labels.uniq
end

def testflight_review_submission_rejected?(message)
  text = message.to_s
  return false if text.empty?

  text.match?(/required|missing|invalid|betaAppReview|betaAppLocalization|test information/i) &&
    !review_fields_named_in_error(text).empty?
end

def present_on_any?(items, key)
  Array(items).any? { |item| field_present?(item, key) }
end

def field_present?(object, key)
  !field_text(object, key).empty?
end

def field_text(object, key)
  return "" if object.nil?

  value = if object.respond_to?(key)
            object.public_send(key)
          elsif object.respond_to?(:[])
            object[key].nil? ? object[key.to_s] : object[key]
          end
  value.to_s.strip
end

def boolean_field?(object, key)
  value = if object.respond_to?(key)
            object.public_send(key)
          elsif object.respond_to?(:[])
            object[key].nil? ? object[key.to_s] : object[key]
          end
  value == true || value.to_s == "true"
end
