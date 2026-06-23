require "net/http"

module DriveCvDownload
  extend ActiveSupport::Concern

  private

  def stream_drive_cv(cv_analysis)
    token = cv_analysis.user.fresh_google_access_token
    unless token
      redirect_back fallback_location: root_path, alert: "Unable to fetch CV — Google authorization required."
      return
    end

    file_id  = cv_analysis.drive_file_id
    filename = (cv_analysis.drive_file_name.presence || "cv.pdf")
    filename += ".pdf" unless filename.end_with?(".pdf", ".docx", ".doc")

    uri  = URI("https://www.googleapis.com/drive/v3/files/#{file_id}?alt=media")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"

    http.request(request) do |response|
      if response.code == "200"
        content_type = response["Content-Type"].presence || "application/octet-stream"
        send_data response.body, filename: filename, type: content_type, disposition: "attachment"
      else
        redirect_back fallback_location: root_path, alert: "Could not download CV (Drive returned #{response.code})."
      end
    end
  end
end
