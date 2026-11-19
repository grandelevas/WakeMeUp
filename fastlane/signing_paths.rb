# frozen_string_literal: true

require "base64"
require "fileutils"
require "open3"
require "openssl"
require "tmpdir"

# Fastlane evaluates the lane inside fastlane/, then runs each action from the
# repo root. Relative paths therefore mean two different directories. These
# constants are absolute, from this file's own location, so both sides agree.
module WakeMeUpSigning
  REPO_ROOT = File.expand_path("..", __dir__)
  SIGNING_DIR = File.expand_path("../signing", __dir__)
  SIGNING_OUT = File.expand_path("../signing-out", __dir__)
  XCODEPROJ = File.expand_path("../WakeMeUp.xcodeproj", __dir__)
  BUILD_DIR = File.expand_path("../build", __dir__)
  # Apple certificate id of the p12 stored in DISTRIBUTION_CERTIFICATE_P12_BASE64.
  EXPECTED_DISTRIBUTION_CERTIFICATE_ID = "R59NUQ72U9"

  module_function

  def absolute_repo_path(path)
    path = path.to_s
    return path if path.start_with?("/")

    File.expand_path(path, REPO_ROOT)
  end

  def decode_p12_base64(encoded)
    cleaned = encoded.to_s.gsub(/[[:space:]]/, "")
    raise "DISTRIBUTION_CERTIFICATE_P12_BASE64 is empty. The password was not checked." if cleaned.empty?

    begin
      der = Base64.strict_decode64(cleaned)
    rescue ArgumentError
      raise "DISTRIBUTION_CERTIFICATE_P12_BASE64 is not valid base64 after removing whitespace and newlines. Re-encode distribution.p12. The password was not checked."
    end
    raise "DISTRIBUTION_CERTIFICATE_P12_BASE64 decoded to empty data. The password was not checked." if der.empty?

    der
  end

  def read_pkcs12(der, password)
    OpenSSL::PKCS12.new(der, password)
  rescue OpenSSL::PKCS12::PKCS12Error => error
    detail = error.message.to_s
    if detail.match?(/mac verify|invalid password|password/i)
      raise "The p12 decoded, but its MAC check failed. DISTRIBUTION_CERTIFICATE_PASSWORD does not match this file."
    end
    raise "The decoded bytes are not a readable PKCS#12 file (#{detail}). DISTRIBUTION_CERTIFICATE_P12_BASE64 may be truncated or the wrong file."
  end

  # macOS `security import` rejects OpenSSL 3's default AES-256/PBKDF2/SHA-256
  # PKCS#12 with "MAC verification failed". PBE-SHA1-3DES and a SHA-1 MAC are
  # the algorithms the Security framework still accepts. The password is passed
  # to openssl as file:, never as a command argument.
  def write_legacy_p12(key:, certificate:, password:, destination:)
    raise "DISTRIBUTION_CERTIFICATE_PASSWORD is empty" if password.to_s.empty?

    Dir.mktmpdir("wakemeup-legacy-p12") do |dir|
      key_path = File.join(dir, "key.pem")
      cert_path = File.join(dir, "cert.pem")
      pass_path = File.join(dir, "pass")
      File.write(key_path, key.to_pem)
      File.write(cert_path, certificate.to_pem)
      File.write(pass_path, password)
      File.chmod(0o600, key_path, pass_path)

      attempts = [
        ["-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "SHA1"],
        ["-legacy"],
        ["-descert", "-macalg", "SHA1"]
      ]
      errors = []
      attempts.each do |extra|
        FileUtils.rm_f(destination)
        _stdout, stderr, status = Open3.capture3(
          "openssl", "pkcs12", "-export",
          "-inkey", key_path,
          "-in", cert_path,
          "-out", destination,
          "-name", "WakeMeUp Distribution",
          *extra,
          "-passout", "file:#{pass_path}"
        )
        next unless status.success? && File.file?(destination) && !File.empty?(destination)

        parsed = begin
          OpenSSL::PKCS12.new(File.binread(destination), password)
        rescue OpenSSL::PKCS12::PKCS12Error
          nil
        end
        return destination if parsed&.certificate&.to_der == certificate.to_der

        errors << scrub(stderr, password)
      end
      raise "Could not write a macOS-compatible PKCS#12 file. #{errors.compact.reject(&:empty?).join(' | ')}"
    end
  end

  # cert stores a DER .cer and a PEM private key whose name ends in .p12.
  def export_distribution_p12(output_dir:, certificate_path:, key_path:, password:)
    raise "DISTRIBUTION_CERTIFICATE_PASSWORD is empty" if password.to_s.empty?
    raise "cert did not leave #{certificate_path}" unless File.file?(certificate_path)
    raise "cert did not leave #{key_path}" unless File.file?(key_path)

    key = OpenSSL::PKey.read(File.binread(key_path))
    certificate = OpenSSL::X509::Certificate.new(File.binread(certificate_path))
    destination = File.join(output_dir, "distribution.p12")
    write_legacy_p12(key: key, certificate: certificate, password: password, destination: destination)
    File.chmod(0o600, destination)
    File.delete(key_path) unless File.expand_path(key_path) == File.expand_path(destination)
    File.write(
      File.join(output_dir, "README.txt"),
      "Encode distribution.p12 only, with the DISTRIBUTION_CERTIFICATE_PASSWORD already stored in GitHub. Do not paste the file into chat.\n"
    )
    destination
  end

  # Apple Distribution certificates put the 10-character team id in OU.
  def certificate_team_id(certificate)
    units = certificate.subject.to_a.filter_map do |name, value, _type|
      text = value.to_s.strip
      text if name == "OU" && !text.empty?
    end
    team_ids = units.grep(/\A[A-Z0-9]{10}\z/)
    return team_ids.first if team_ids.length == 1

    subject = certificate.subject.to_s
    if team_ids.length > 1
      raise "The distribution certificate has more than one team id in OU (#{team_ids.join(', ')}). Subject: #{subject}"
    end
    raise "The distribution certificate has no team id in its OU. Subject: #{subject}"
  end

  def assert_team_matches_certificate!(certificate, configured_team_id)
    ou = certificate_team_id(certificate)
    configured = configured_team_id.to_s.strip
    return if configured == ou

    shown = configured.empty? ? "(empty)" : configured
    raise <<~MSG.strip
      APPLE_TEAM_ID is #{shown}, but the imported distribution certificate's OU is #{ou}.
      Update the APPLE_TEAM_ID secret to #{ou} and rerun upload-testflight.
      No Apple API call was made and the certificate was not imported.
    MSG
  end

  def scrub(text, password)
    cleaned = text.to_s
    cleaned = cleaned.gsub(password, "[redacted]") unless password.to_s.empty?
    cleaned.strip
  end
end
