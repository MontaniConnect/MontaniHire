ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/authentication_helper"

class ActiveSupport::TestCase
  fixtures :all

  # Creates an isolated user+org pair via UserRegistrationService so tests
  # always satisfy the organisation FK constraint on related records.
  def build_user(email: nil)
    email ||= "u_#{SecureRandom.hex(4)}@example.com"
    UserRegistrationService.new(email: email, name: "Test User").call.user
  end
end

class ActionDispatch::IntegrationTest
  include AuthenticationHelper
end
