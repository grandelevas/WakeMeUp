# frozen_string_literal: true

require "openssl"

# Fastlane evaluates the lane inside fastlane/, then runs each action from the
# repo root. Relative paths therefore mean two different directories. These
# constants are absolute, from this file's own location, so both sides agree.
module WakeMeUpSigning
  REPO_ROOT = File.expand_path("..", __dir__)
  SIGNING_DIR = File.expand_path("../signing", __dir__)
  SIGNING_OUT = File.expand_path("../signing-out", __dir__)
  XCODEPROJ = File.expand_path("../WakeMeUp.xcodeproj", __dir__)
  BUILD_DIR = File.expand_path("../build", __dir__)

  module_function

  def absolute_repo_path(path)
    path = path.to_s
    return path if path.start_with?("/")

    File.expand_path(path, REPO_ROOT)
  end

  # cert stores a DER .cer and a PEM private key whose name ends in .p12.
  # import_certificate needs a real PKCS#12 archive. The password stays in
  # process and is never placed on a command line.
  def export_distribution_p12(output_dir:, certificate_path:, key_path:, password:)
    raise "DISTRIBUTION_CERTIFICATE_PASSWORD is empty" if password.to_s.empty?
    raise "cert did not leave #{certificate_path}" unless File.file?(certificate_path)
    raise "cert did not leave #{key_path}" unless File.file?(key_path)

    key = OpenSSL::PKey.read(File.binread(key_path))
    certificate = OpenSSL::X509::Certificate.new(File.binread(certificate_path))
    archive = OpenSSL::PKCS12.create(password, "WakeMeUp Distribution", key, certificate)
    destination = File.join(output_dir, "distribution.p12")
    File.binwrite(destination, archive.to_der)
    File.chmod(0o600, destination)
    File.delete(key_path) unless File.expand_path(key_path) == File.expand_path(destination)
    File.write(
      File.join(output_dir, "README.txt"),
      "Encode distribution.p12 only, with the DISTRIBUTION_CERTIFICATE_PASSWORD already stored in GitHub. Do not paste the file into chat.\n"
    )
    destination
  end
end
