# frozen_string_literal: true

require_relative "helper"
require "rubygems"
require "rubygems/command"
require "rubygems/gemcutter_utilities"

class TestGemGemcutterUtilities < Gem::TestCase
  def setup
    super

    credential_setup

    # below needed for random testing, class property
    Gem.configuration.disable_default_gem_server = nil

    ENV["RUBYGEMS_HOST"] = nil
    ENV["GEM_HOST_OTP_CODE"] = nil
    Gem.configuration.rubygems_api_key = nil

    @cmd = Gem::Command.new "", "summary"
    @cmd.extend Gem::GemcutterUtilities
  end

  def teardown
    ENV["RUBYGEMS_HOST"] = nil
    ENV["GEM_HOST_OTP_CODE"] = nil
    Gem.configuration.rubygems_api_key = nil

    credential_teardown

    super
  end

  def test_alternate_key_alternate_host
    keys = {
      :rubygems_api_key => "KEY",
      "http://rubygems.engineyard.com" => "EYKEY",
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write keys.to_yaml
    end

    ENV["RUBYGEMS_HOST"] = "http://rubygems.engineyard.com"

    Gem.configuration.load_api_keys

    assert_equal "EYKEY", @cmd.api_key
  end

  def test_api_key
    keys = { :rubygems_api_key => "KEY" }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write keys.to_yaml
    end

    Gem.configuration.load_api_keys

    assert_equal "KEY", @cmd.api_key
  end

  def test_api_key_override
    keys = { :rubygems_api_key => "KEY", :other => "OTHER" }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write keys.to_yaml
    end

    Gem.configuration.load_api_keys

    @cmd.add_key_option
    @cmd.handle_options %w[--key other]

    assert_equal "OTHER", @cmd.api_key
  end

  def test_host
    assert_equal "https://rubygems.org", @cmd.host
  end

  def test_host_RUBYGEMS_HOST
    ENV["RUBYGEMS_HOST"] = "https://other.example"

    assert_equal "https://other.example", @cmd.host
  end

  def test_host_RUBYGEMS_HOST_empty
    ENV["RUBYGEMS_HOST"] = ""

    assert_equal "https://rubygems.org", @cmd.host
  end

  def test_sign_in
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")

    assert_match %r{Enter your RubyGems.org credentials.}, @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match %r{Signed in.}, @sign_in_ui.output

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal api_key, credentials[:rubygems_api_key]
  end

  def test_sign_in_with_host
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"

    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK"), "http://example.com", ["http://example.com"]

    assert_match "Enter your http://example.com credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match %r{Signed in.}, @sign_in_ui.output

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal api_key, credentials["http://example.com"]
  end

  def test_sign_in_with_host_nil
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"

    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK"), nil, [nil]

    assert_match "Enter your RubyGems.org credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match %r{Signed in.}, @sign_in_ui.output

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal api_key, credentials[:rubygems_api_key]
  end

  def test_sign_in_with_host_ENV
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK"), "http://example.com"

    assert_match "Enter your http://example.com credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match %r{Signed in.}, @sign_in_ui.output

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal api_key, credentials["http://example.com"]
  end

  def test_sign_in_skips_with_existing_credentials
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    Gem.configuration.rubygems_api_key = api_key

    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")

    assert_equal "", @sign_in_ui.output
  end

  def test_sign_in_skips_with_key_override
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    Gem.configuration.api_keys[:KEY] = "other"
    @cmd.options[:key] = :KEY
    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")

    assert_equal "", @sign_in_ui.output
  end

  def test_sign_in_with_other_credentials_doesnt_overwrite_other_keys
    api_key       = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    other_api_key = "f46dbb18bb6a9c97cdc61b5b85c186a17403cdcbf"

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Hash[:other_api_key, other_api_key].to_yaml
    end
    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")

    assert_match %r{Enter your RubyGems.org credentials.}, @sign_in_ui.output
    assert_match %r{Signed in.}, @sign_in_ui.output

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal api_key, credentials[:rubygems_api_key]
    assert_equal other_api_key, credentials[:other_api_key]
  end

  def test_sign_in_with_bad_credentials
    assert_raise Gem::MockGemUi::TermError do
      util_sign_in HTTPResponseFactory.create(body: "Access Denied.", code: 403, msg: "Forbidden")
    end

    assert_match %r{Enter your RubyGems.org credentials.}, @sign_in_ui.output
    assert_match %r{Access Denied.}, @sign_in_ui.output
  end

  def test_signin_with_env_otp_code
    ENV["GEM_HOST_OTP_CODE"] = "111111"
    api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"

    util_sign_in HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")

    assert_match "Signed in with API key:", @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_correct_otp_code
    api_key       = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
    response_fail = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."

    util_sign_in(proc do
      @call_count ||= 0
      if (@call_count += 1).odd?
        HTTPResponseFactory.create(body: response_fail, code: 401, msg: "Unauthorized")
      else
        HTTPResponseFactory.create(body: api_key, code: 200, msg: "OK")
      end
    end, nil, [], "111111\n")

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @sign_in_ui.output
    assert_match "Code: ", @sign_in_ui.output
    assert_match "Signed in with API key:", @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_incorrect_otp_code
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."

    assert_raise Gem::MockGemUi::TermError do
      util_sign_in HTTPResponseFactory.create(body: response, code: 401, msg: "Unauthorized"), nil, [], "111111\n"
    end

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @sign_in_ui.output
    assert_match "Code: ", @sign_in_ui.output
    assert_match response, @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def util_sign_in(response, host = nil, args = [], extra_input = "")
    email            = "you@example.com"
    password         = "secret"
    profile_response = HTTPResponseFactory.create(body: "mfa: disabled\n", code: 200, msg: "OK")

    if host
      ENV["RUBYGEMS_HOST"] = host
    else
      host = Gem.host
    end

    @fetcher = Gem::FakeFetcher.new
    @fetcher.data["#{host}/api/v1/api_key"] = response
    @fetcher.data["#{host}/api/v1/profile/me.yaml"] = profile_response
    Gem::RemoteFetcher.fetcher = @fetcher

    @sign_in_ui = Gem::MockGemUi.new("#{email}\n#{password}\n\n\n\n\n\n\n\n\n" + extra_input)

    use_ui @sign_in_ui do
      if args.length > 0
        @cmd.sign_in(*args)
      else
        @cmd.sign_in
      end
    end
  end

  def test_verify_api_key
    keys = { :other => "a5fdbb6ba150cbb83aad2bb2fede64cf040453903" }
    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    assert_equal "a5fdbb6ba150cbb83aad2bb2fede64cf040453903",
                 @cmd.verify_api_key(:other)
  end

  def test_verify_missing_api_key
    assert_raise Gem::MockGemUi::TermError do
      @cmd.verify_api_key :missing
    end
  end
end
