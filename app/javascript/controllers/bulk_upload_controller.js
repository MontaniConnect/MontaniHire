import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tabSingle", "tabBulk", "panelSingle", "panelBulk",
                    "input", "prompt", "fileList", "submitBtn"]

  showSingle() {
    this.panelSingleTarget.style.display = "block"
    this.panelBulkTarget.style.display   = "none"
    this.tabSingleTarget.style.borderBottomColor = "#1a1a1a"
    this.tabSingleTarget.style.color             = "#1a1a1a"
    this.tabSingleTarget.style.fontWeight        = "600"
    this.tabBulkTarget.style.borderBottomColor   = "transparent"
    this.tabBulkTarget.style.color               = "#888"
    this.tabBulkTarget.style.fontWeight          = "500"
  }

  showBulk() {
    this.panelSingleTarget.style.display = "none"
    this.panelBulkTarget.style.display   = "block"
    this.tabBulkTarget.style.borderBottomColor   = "#1a1a1a"
    this.tabBulkTarget.style.color               = "#1a1a1a"
    this.tabBulkTarget.style.fontWeight          = "600"
    this.tabSingleTarget.style.borderBottomColor = "transparent"
    this.tabSingleTarget.style.color             = "#888"
    this.tabSingleTarget.style.fontWeight        = "500"
  }

  preview() {
    const files = Array.from(this.inputTarget.files)
    if (!files.length) return

    this.promptTarget.style.display  = "none"
    this.fileListTarget.style.display = "block"
    this.fileListTarget.innerHTML = files.map(f => {
      const name = f.name.replace(/\.[^.]+$/, "").replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase())
      const size = (f.size / 1024 / 1024).toFixed(1)
      return `<li style="padding: 0.3rem 0; font-size: 0.85rem; border-bottom: 1px solid #f0f0f0; display:flex; justify-content:space-between; gap:1rem;">
        <span style="font-weight:500; color:#1a1a1a;">${name}</span>
        <span style="color:#999; white-space:nowrap;">${size} MB</span>
      </li>`
    }).join("")

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.textContent = `Upload & Analyse ${files.length} CV${files.length !== 1 ? "s" : ""}`
    }

    this.element.addEventListener("submit", () => {
      if (this.hasSubmitBtnTarget) {
        this.submitBtnTarget.disabled = true
        this.submitBtnTarget.textContent = "Uploading…"
      }
    }, { once: true })
  }
}
