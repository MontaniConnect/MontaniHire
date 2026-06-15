import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileIdInput", "fileNameInput", "fileLabel", "button", "folderInput", "candidateName"]
  static values  = { accessToken: String, apiKey: String, clientId: String, mimeTypes: String, nameFieldId: String, folderMode: Boolean }

  connect() {
    this._pickerLoaded = false
  }

  open(event) {
    event.preventDefault()
    if (this._pickerLoaded) {
      this._showPicker()
    } else {
      this._loadPickerApi(() => this._showPicker())
    }
  }

  _loadPickerApi(callback) {
    if (window.gapi?.picker) {
      this._pickerLoaded = true
      callback()
      return
    }

    const script = document.createElement("script")
    script.src   = "https://apis.google.com/js/api.js"
    script.onload = () => {
      window.gapi.load("picker", () => {
        this._pickerLoaded = true
        callback()
      })
    }
    document.head.appendChild(script)
  }

  _showPicker() {
    const token   = this.accessTokenValue
    const apiKey  = this.apiKeyValue

    if (!token) {
      alert("Google Drive is not connected. Please connect your account first.")
      return
    }

    const defaultMimes = "video/mp4,video/quicktime,video/webm,audio/mpeg,audio/mp4,audio/wav,video/x-msvideo"
    const mimeTypes   = this.mimeTypesValue || defaultMimes
    const folderId    = this._parseFolderId() || this._savedFolderId()

    let view
    if (this.folderModeValue) {
      view = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
        .setIncludeFolders(true)
        .setSelectFolderEnabled(true)
      if (folderId) {
        view.setParent(folderId)
        view.setMode(google.picker.DocsViewMode.LIST)
      }
    } else {
      view = new google.picker.DocsView(google.picker.ViewId.DOCS)
        .setMimeTypes(mimeTypes)
        .setIncludeFolders(true)
        .setSelectFolderEnabled(false)
      if (folderId) {
        view.setParent(folderId)
        view.setMode(google.picker.DocsViewMode.LIST)
      }
    }

    const picker = new google.picker.PickerBuilder()
      .addView(view)
      .setOAuthToken(token)
      .setDeveloperKey(apiKey)
      .setCallback((data) => this._onPicked(data))
      .build()

    picker.setVisible(true)
  }

  _parseFolderId() {
    if (!this.hasFolderInputTarget) return null
    const raw = this.folderInputTarget.value.trim()
    if (!raw) return null
    // Accept a full Drive URL like https://drive.google.com/drive/folders/FOLDER_ID
    // or a bare folder ID
    const match = raw.match(/\/folders\/([a-zA-Z0-9_-]+)/)
    return match ? match[1] : raw
  }

  _savedFolderId() {
    try { return localStorage.getItem("drivePicker_lastFolderId") } catch(e) { return null }
  }

  _saveFolderId(id) {
    try { localStorage.setItem("drivePicker_lastFolderId", id) } catch(e) {}
  }

  _onPicked(data) {
    if (data[google.picker.Response.ACTION] !== google.picker.Action.PICKED) return

    const doc      = data[google.picker.Response.DOCUMENTS][0]
    const id       = doc[google.picker.Document.ID]
    const name     = doc[google.picker.Document.NAME]
    const parentId = doc["parentId"] || doc[google.picker.Document.PARENT_ID]

    if (parentId) this._saveFolderId(parentId)

    this.fileIdInputTarget.value   = id
    this.fileNameInputTarget.value = name
    this.fileLabelTarget.textContent = name
    this.fileLabelTarget.style.display = "block"

    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = "Change file"
    }

    const nameField = this.hasCandidateNameTarget
      ? this.candidateNameTarget
      : (this.hasNameFieldIdValue && document.getElementById(this.nameFieldIdValue))

    if (nameField && !nameField.value.trim()) {
      const stem = name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim()
      nameField.value = stem
    }
  }
}
