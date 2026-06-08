import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "input"]

  connect() {
    this.element.addEventListener("submit", this.onSubmit.bind(this))
  }

  onSubmit() {
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.textContent = "Submitting…"
    }
  }
}
