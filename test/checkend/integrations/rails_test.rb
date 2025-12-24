# frozen_string_literal: true

require 'test_helper'
require 'checkend/integrations/rails'

# Test controller methods in isolation (without full Rails)
class ControllerMethodsTest < Minitest::Test
  include CheckendTestHelper

  # Mock controller for testing
  class MockController
    # Define stub methods BEFORE including the module
    def self.before_action(_method_name)
      # Store for testing but don't actually call
    end

    def self.after_action(_method_name)
      # Store for testing but don't actually call
    end

    include Checkend::Integrations::Rails::ControllerMethods

    attr_accessor :controller_name, :action_name, :request, :current_user_value

    def initialize
      @controller_name = 'users'
      @action_name = 'show'
      @request = MockRequest.new
      @current_user_value = nil
    end

    def respond_to?(method, include_private = false) # rubocop:disable Style/OptionalBooleanParameter
      return true if method == :current_user && @current_user_value

      super
    end

    def current_user
      @current_user_value
    end
  end

  class MockRequest
    def request_id
      'req-12345'
    end
  end

  class MockUser
    attr_accessor :id, :email, :name

    def initialize(id:, email:, name: nil)
      @id = id
      @email = email
      @name = name
    end
  end

  def test_controller_methods_module_exists
    assert defined?(Checkend::Integrations::Rails::ControllerMethods)
  end

  def test_extract_user_info_with_id_and_email
    controller = MockController.new
    user = MockUser.new(id: 123, email: 'test@example.com', name: 'Test User')

    info = controller.send(:extract_user_info, user)

    assert_equal 123, info[:id]
    assert_equal 'test@example.com', info[:email]
    assert_equal 'Test User', info[:name]
  end

  def test_extract_user_info_with_minimal_attributes
    controller = MockController.new
    user = Object.new
    def user.id
      456
    end

    info = controller.send(:extract_user_info, user)

    assert_equal 456, info[:id]
    assert_nil info[:email]
    assert_nil info[:name]
  end

  def test_extract_user_name_tries_multiple_methods
    controller = MockController.new

    # Test with full_name
    user1 = Object.new
    def user1.full_name
      'Full Name'
    end

    assert_equal 'Full Name', controller.send(:extract_user_name, user1)

    # Test with display_name
    user2 = Object.new
    def user2.display_name
      'Display Name'
    end

    assert_equal 'Display Name', controller.send(:extract_user_name, user2)

    # Test with username
    user3 = Object.new
    def user3.username
      'username123'
    end

    assert_equal 'username123', controller.send(:extract_user_name, user3)

    # Test with no name method
    user4 = Object.new

    assert_nil controller.send(:extract_user_name, user4)
  end

  def test_checkend_set_request_context
    configure_checkend
    controller = MockController.new

    controller.send(:checkend_set_request_context)

    assert_equal 'users', Checkend.context[:controller]
    assert_equal 'show', Checkend.context[:action]
    assert_equal 'req-12345', Checkend.context[:request_id]
  end

  def test_checkend_set_request_context_with_user
    configure_checkend
    controller = MockController.new
    controller.current_user_value = MockUser.new(id: 789, email: 'user@example.com')

    controller.send(:checkend_set_request_context)

    assert_equal 789, Checkend.current_user[:id]
    assert_equal 'user@example.com', Checkend.current_user[:email]
  end

  def test_checkend_set_request_context_without_user
    configure_checkend
    controller = MockController.new
    controller.current_user_value = nil

    controller.send(:checkend_set_request_context)

    # Context should still be set
    assert_equal 'users', Checkend.context[:controller]
    # But no user should be set
    assert_nil Checkend.current_user
  end

  def test_checkend_clear_context
    configure_checkend
    Checkend.set_context(test_key: 'value')
    Checkend.set_user(id: 123)

    controller = MockController.new
    controller.send(:checkend_clear_context)

    assert_empty Checkend.context
    assert_nil Checkend.current_user
  end
end

# Test Railtie is only defined when Rails is available
class RailtieDefinitionTest < Minitest::Test
  def test_railtie_not_defined_without_rails
    # Since we don't have Rails loaded, Railtie should not be defined
    refute defined?(Checkend::Integrations::Rails::Railtie),
           'Railtie should not be defined without Rails'
  end
end
