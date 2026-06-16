module AuthenticationHelper
  def sign_in(user)
    post test_sign_in_path, params: { user_id: user.id }
  end
end
