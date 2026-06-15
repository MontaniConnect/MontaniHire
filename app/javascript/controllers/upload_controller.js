import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "zone", "prompt", "filename", "button", "name"]
  static values  = { nameFieldId: String }

  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return

    this.promptTarget.style.display = "none"
    this.filenameTarget.style.display = "block"
    this.filenameTarget.textContent = `${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)`
    this.zoneTarget.style.borderColor = "#1a1a1a"

    const nameField = this.hasNameTarget
      ? this.nameTarget
      : (this.hasNameFieldIdValue && document.getElementById(this.nameFieldIdValue))

    if (nameField && !nameField.value.trim()) {
      const base = file.name.replace(/\.[^.]+$/, "")
      nameField.value = base
        .replace(/[-_]/g, " ")
        .replace(/\b\w/g, c => c.toUpperCase())
    }
  }

  connect() {
    this.element.addEventListener("submit", () => {
      if (this.hasButtonTarget) {
        this.buttonTarget.disabled = true
        this.buttonTarget.textContent = "Uploading…"
      }
    })
  }
}
