module ValidatesLogoUrl
  extend ActiveSupport::Concern

  HTTPS_IMAGE_RE = /\Ahttps:\/\/.+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?\z/i
  LOGO_URL_MESSAGE = "must be an HTTPS URL ending in an image extension (.jpg, .jpeg, .png, .gif, .webp, .svg)".freeze

  included do
    validates_format_of :logo_url,
      with:       HTTPS_IMAGE_RE,
      message:    LOGO_URL_MESSAGE,
      allow_blank: true
  end
end
