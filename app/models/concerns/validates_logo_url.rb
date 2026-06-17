module ValidatesLogoUrl
  extend ActiveSupport::Concern

  included do
    validate :logo_url_format
  end

  def logo_url_format
    return if logo_url.blank?
    unless logo_url =~ URI::DEFAULT_PARSER.make_regexp
      errors.add(:logo_url, "is not a valid URL")
    end
  end
end