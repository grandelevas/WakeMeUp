#!/usr/bin/env ruby
# frozen_string_literal: true

# Proves macOS `security import` accepts the legacy PKCS#12 we write.
# Uses a throwaway key and keychain. Does not call Apple.

require "openssl"
require "shellwords"
require "tmpdir"
require_relative "../fastlane/signing_paths"

def run!(*command)
  ok = system(*command)
  raise "command failed: #{command.first} #{command[1]}" unless ok
end

password = "test-password"
key = OpenSSL::PKey::RSA.new(2048)
certificate = OpenSSL::X509::Certificate.new
certificate.version = 2
certificate.serial = 1
name = OpenSSL::X509::Name.parse("/CN=WakeMeUp Test")
certificate.subject = name
certificate.issuer = name
certificate.public_key = key.public_key
certificate.not_before = Time.now - 60
certificate.not_after = Time.now + 3600
certificate.sign(key, OpenSSL::Digest::SHA256.new)

Dir.mktmpdir("wakemeup-security-import") do |dir|
  p12 = File.join(dir, "distribution.p12")
  keychain = File.join(dir, "test.keychain-db")
  WakeMeUpSigning.write_legacy_p12(
    key: key,
    certificate: certificate,
    password: password,
    destination: p12
  )

  run!("security", "create-keychain", "-p", "", keychain)
  begin
    run!("security", "unlock-keychain", "-p", "", keychain)
    run!(
      "security", "import", p12,
      "-k", keychain,
      "-P", password,
      "-f", "pkcs12",
      "-T", "/usr/bin/codesign",
      "-T", "/usr/bin/security"
    )
    run!(
      "security", "set-key-partition-list",
      "-S", "apple-tool:,apple:,codesign:",
      "-s",
      "-k", "",
      keychain
    )
    # A self-signed cert is not a valid codesigning identity. Import succeeding,
    # and the certificate landing in the keychain, is what `security import`
    # rejected with "MAC verification failed" for an OpenSSL 3 p12.
    certificates = `security find-certificate -a -p #{Shellwords.escape(keychain)}`
    unless certificates.include?("BEGIN CERTIFICATE")
      raise "security import did not store the certificate:\n#{certificates}"
    end
    keys = `security find-key -a #{Shellwords.escape(keychain)}`
    unless keys.include?("key")
      raise "security import did not store the private key:\n#{keys}"
    end
    puts "security import accepted the legacy p12"
  ensure
    system("security", "delete-keychain", keychain)
  end
end
