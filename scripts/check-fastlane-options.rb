#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads fastlane 2.242.0 and checks every action call in fastlane/Fastfile.
# It does not talk to Apple and does not create a certificate.
# Run with: bundle exec ruby scripts/check-fastlane-options.rb

require "openssl"
require "ripper"
require "fastlane"

Fastlane::Actions.load_default_actions

ROOT = File.expand_path("..", __dir__)
FASTFILE = File.join(ROOT, "fastlane", "Fastfile")
SOURCE = File.read(FASTFILE)

ACTIONS = %w[
  app_store_connect_api_key
  setup_ci
  cert
  sigh
  import_certificate
  update_code_signing_settings
  build_app
  upload_to_testflight
  latest_testflight_build_number
].freeze

def action_calls(source)
  tokens = Ripper.lex(source)
  calls = []
  index = 0
  while index < tokens.length
    _position, type, text, = tokens[index]
    unless type == :on_ident && ACTIONS.include?(text)
      index += 1
      next
    end

    cursor = index + 1
    cursor += 1 while cursor < tokens.length && %i[on_sp on_nl on_ignored_nl].include?(tokens[cursor][1])
    unless tokens[cursor] && tokens[cursor][1] == :on_lparen
      index += 1
      next
    end

    depth = 1
    braces = 0
    keys = []
    cursor += 1
    while cursor < tokens.length && depth.positive?
      token_type, token_text = tokens[cursor][1], tokens[cursor][2]
      case token_type
      when :on_lparen
        depth += 1
      when :on_rparen
        depth -= 1
      when :on_lbrace, :on_tlambeg
        braces += 1
      when :on_rbrace
        braces -= 1
      when :on_label
        keys << token_text.sub(/:\z/, "").to_sym if depth == 1 && braces.zero?
      end
      cursor += 1
    end
    calls << [text, keys, tokens[index][0][0]]
    index = cursor
  end
  calls
end

def distribution_certificate(team_id)
  key = OpenSSL::PKey::RSA.new(2048)
  certificate = OpenSSL::X509::Certificate.new
  certificate.version = 2
  certificate.serial = 1
  parts = [["CN", "Apple Distribution: Example#{team_id ? " (#{team_id})" : ""}"]]
  parts << ["OU", team_id] if team_id
  parts.push(["O", "Example"], ["C", "US"])
  certificate.subject = OpenSSL::X509::Name.new(parts)
  certificate.issuer = certificate.subject
  certificate.public_key = key.public_key
  certificate.not_before = Time.now - 60
  certificate.not_after = Time.now + 3600
  certificate.sign(key, OpenSSL::Digest::SHA256.new)
  certificate
end

calls = action_calls(SOURCE)
abort("No fastlane action calls found in #{FASTFILE}") if calls.empty?

failures = []
calls.each do |name, keys, line|
  action = Fastlane::Actions.action_class_ref(name)
  if action.nil?
    failures << "#{name} (line #{line}) is not a fastlane #{Fastlane::VERSION} action"
    next
  end
  allowed = action.available_options.map(&:key)
  unknown = keys - allowed
  unknown.each do |key|
    failures << "#{name} (line #{line}) has no option :#{key}. Allowed: #{allowed.join(', ')}"
  end
end

unless SOURCE.include?('CI_KEYCHAIN_PASSWORD = ""')
  failures << "CI_KEYCHAIN_PASSWORD must stay an empty string. setup_ci hardcodes that password."
end

setup_calls = calls.select { |name, _, _| name == "setup_ci" }
if setup_calls.empty? || setup_calls.any? { |_, keys, _| keys.include?(:keychain_password) }
  failures << "setup_ci must not be passed :keychain_password"
end
unless setup_calls.all? { |_, keys, _| keys.include?(:keychain_name) && keys.include?(:force) }
  failures << "setup_ci must set :keychain_name and :force"
end

%w[cert import_certificate].each do |name|
  relevant = calls.select { |action, _, _| action == name }
  if relevant.empty? || relevant.any? { |_, keys, _| !keys.include?(:keychain_password) || !keys.include?(:keychain_path) }
    failures << "#{name} must pass :keychain_path and :keychain_password so it uses the empty-password keychain setup_ci creates"
  end
end

# Lane code runs in fastlane/; actions run in the repo root. A relative
# output path is therefore a different directory in each place.
[
  [/output_path:\s*["']/, "output_path must be WakeMeUpSigning::SIGNING_OUT, not a relative string"],
  [/key_filepath:\s*["']/, "key_filepath must be an absolute path under WakeMeUpSigning::SIGNING_DIR"],
  [/certificate_path:\s*["']/, "certificate_path must be an absolute path under WakeMeUpSigning::SIGNING_DIR"],
  [/project:\s*["']/, "build_app project must be WakeMeUpSigning::XCODEPROJ"],
  [/output_directory:\s*["']/, "build_app output_directory must be WakeMeUpSigning::BUILD_DIR"]
].each do |pattern, message|
  failures << message if SOURCE.match?(pattern)
end

unless SOURCE.include?("WakeMeUpSigning::SIGNING_OUT") &&
       SOURCE.include?("SharedValues::CERT_FILE_PATH")
  failures << "bootstrap must export the p12 from CERT_FILE_PATH into SIGNING_OUT"
end

bootstrap = SOURCE[/lane :bootstrap_signing do(.*?)(?=\n  desc |\n  lane :beta)/m]
guard_at = bootstrap.to_s.index("refuse_bootstrap_when_p12_present!")
token_at = bootstrap.to_s.index("asc_key")
if guard_at.nil? || token_at.nil? || guard_at > token_at
  failures << "bootstrap_signing must refuse a stored p12 secret before app_store_connect_api_key"
end

beta = SOURCE[/lane :beta do(.*)\z/m].to_s
team_at = beta.index("require_certificate_team!")
beta_token_at = beta.index("asc_key")
if team_at.nil? || beta_token_at.nil? || team_at > beta_token_at
  failures << "beta must compare APPLE_TEAM_ID to the certificate OU before app_store_connect_api_key"
end
version_at = beta.index("next_bundle_version")
build_at = beta.index("build_app(")
unless version_at && build_at && version_at < build_at && beta.include?("CURRENT_PROJECT_VERSION=")
  failures << "beta must set CURRENT_PROJECT_VERSION from next_bundle_version before build_app"
end
unless beta.include?("GITHUB_RUN_NUMBER") || SOURCE.include?("GITHUB_RUN_NUMBER")
  failures << "bundle versions must consider GITHUB_RUN_NUMBER"
end
unless SOURCE.match?(/def team_id\n  ENV\.fetch\("APPLE_TEAM_ID"\)\nend/)
  failures << "team_id must be ENV.fetch(\"APPLE_TEAM_ID\") with no default"
end

forbidden_team = %w[T9M8 DVS2UD].join
Dir.glob(File.join(ROOT, "**/*.{rb,yml,yaml,md,plist,swift,entitlements,sh,py,txt,json}")).each do |path|
  next if path.include?("/vendor/") || path.include?("/.git/")
  next unless File.file?(path)

  relative = path.delete_prefix("#{ROOT}/")
  failures << "#{relative} hardcodes #{forbidden_team}" if File.read(path).include?(forbidden_team)
end
if File.read(File.join(ROOT, "project.yml")).match?(/^\s*DEVELOPMENT_TEAM:/)
  failures << "project.yml must not set DEVELOPMENT_TEAM. Release signing uses APPLE_TEAM_ID."
end

require_relative "../fastlane/signing_paths"

expected_out = File.join(ROOT, "signing-out")
unless WakeMeUpSigning::SIGNING_OUT == expected_out && File.absolute_path?(WakeMeUpSigning::SIGNING_OUT)
  failures << "SIGNING_OUT must be the absolute repo-root signing-out directory"
end
unless WakeMeUpSigning::SIGNING_DIR == File.join(ROOT, "signing")
  failures << "SIGNING_DIR must be the absolute repo-root signing directory"
end
unless File.absolute_path?(WakeMeUpSigning::XCODEPROJ) && File.absolute_path?(WakeMeUpSigning::BUILD_DIR)
  failures << "XCODEPROJ and BUILD_DIR must be absolute"
end

begin
  require "tmpdir"
  Dir.mktmpdir("wakemeup-p12") do |dir|
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = OpenSSL::X509::Name.parse("/CN=WakeMeUp Test")
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    certificate.sign(key, OpenSSL::Digest::SHA256.new)

    cer_path = File.join(dir, "TESTCERT.cer")
    key_path = File.join(dir, "TESTCERT.p12")
    File.binwrite(cer_path, certificate.to_der)
    File.write(key_path, key.to_pem)
    password = "test-password"

    Dir.chdir(Dir.tmpdir) do
      WakeMeUpSigning.export_distribution_p12(
        output_dir: dir,
        certificate_path: cer_path,
        key_path: key_path,
        password: password
      )
    end

    archive_path = File.join(dir, "distribution.p12")
    raise "distribution.p12 was not written" unless File.file?(archive_path)
    raise "PEM key was left next to the archive" if File.exist?(key_path)
    opened = OpenSSL::PKCS12.new(File.binread(archive_path), password)
    raise "certificate did not round-trip" unless opened.certificate.to_der == certificate.to_der
    raise "private key did not round-trip" unless opened.key.to_pem == key.to_pem

    modern = OpenSSL::PKCS12.create(password, "WakeMeUp Distribution", key, certificate)
    wrapped = Base64.encode64(modern.to_der)
    der = WakeMeUpSigning.decode_p12_base64("\n#{wrapped.scan(/.{1,64}/).join("\n")}\n")
    parsed = WakeMeUpSigning.read_pkcs12(der, password)
    legacy_path = File.join(dir, "from-wrapped.p12")
    WakeMeUpSigning.write_legacy_p12(
      key: parsed.key,
      certificate: parsed.certificate,
      password: password,
      destination: legacy_path
    )
    legacy = OpenSSL::PKCS12.new(File.binread(legacy_path), password)
    raise "wrapped base64 cert mismatch" unless legacy.certificate.to_der == certificate.to_der

    begin
      WakeMeUpSigning.read_pkcs12(der, "not-the-password")
      raise "wrong password was accepted"
    rescue RuntimeError => error
      raise "password error was unclear: #{error.message}" unless error.message.include?("DISTRIBUTION_CERTIFICATE_PASSWORD")
    end

    begin
      WakeMeUpSigning.decode_p12_base64("!!!!")
      raise "invalid base64 was accepted"
    rescue RuntimeError => error
      raise "base64 error was unclear: #{error.message}" unless error.message.include?("not valid base64")
    end

    matching = distribution_certificate("AAAAAAAAAA")
    WakeMeUpSigning.assert_team_matches_certificate!(matching, "AAAAAAAAAA")
    begin
      WakeMeUpSigning.assert_team_matches_certificate!(matching, "BBBBBBBBBB")
      raise "a different team id was accepted"
    rescue RuntimeError => error
      unless error.message.include?("APPLE_TEAM_ID is BBBBBBBBBB") && error.message.include?("OU is AAAAAAAAAA")
        raise "team mismatch did not print both ids: #{error.message}"
      end
    end
    begin
      WakeMeUpSigning.certificate_team_id(distribution_certificate(nil))
      raise "a certificate without OU was accepted"
    rescue RuntimeError => error
      raise "missing OU error was unclear: #{error.message}" unless error.message.include?("no team id")
    end
  end
rescue StandardError => error
  failures << "export_distribution_p12 round-trip failed: #{error.message}"
end

if failures.empty?
  puts "fastlane #{Fastlane::VERSION}: #{calls.length} action calls, every option exists"
  calls.each do |name, keys, line|
    puts "  #{name}:#{line} #{keys.join(', ')}"
  end
else
  warn failures.join("\n")
  exit 1
end
