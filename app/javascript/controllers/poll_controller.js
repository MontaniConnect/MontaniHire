import { Controller } from "@hotwired/stimulus"

// Polls the current page every 3s until the analysis is done or failed.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timer = setInterval(() => this.reload(), 3000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async reload() {
    const res = await fetch(this.urlValue, { headers: { Accept: "text/vnd.turbo-stream.html, text/html" } })
    if (!res.ok) return
    const html = await res.text()
    const parser = new DOMParser()
    const doc = parser.parseFromString(html, "text/html")
    const badge = doc.querySelector(".badge")
    const status = badge ? badge.textContent.trim() : ""

    if (status === "completed" || status === "failed") {
      clearInterval(this.timer)
      window.location.reload()
    }
  }
}
