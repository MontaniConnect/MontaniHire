Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src  :self, "https://apis.google.com"
  policy.style_src   :self, :unsafe_inline
  policy.img_src     :self, :data, "https:"
  policy.font_src    :self
  policy.connect_src :self, "https://apis.google.com", "https://www.googleapis.com", "https://accounts.google.com"
  policy.frame_src   "https://drive.google.com", "https://accounts.google.com"
  policy.object_src  :none
  policy.base_uri    :self
  policy.form_action :self
end

Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
