import http from './http'

export interface AttachmentView {
  attachmentId: number
  bizType: string
  bizTypeLabel: string
  bizId: string
  fileName: string
  fileSize: number
  fileType: string
  uploadedBy?: string | null
  uploadedByName?: string | null
  uploadedAt?: string | null
  downloadUrl: string
}

export interface UploadRules {
  allowedExtensions: string[]
  maxBytes: number
}

export interface UploadResult {
  attachment: AttachmentView
  scanResult: string
}

export const attachmentApi = {
  rules: () => http.get<UploadRules>('/attachments/rules').then((r) => r.data),

  list: (bizType: string, bizId: string) =>
    http
      .get<AttachmentView[]>('/attachments', { params: { bizType, bizId } })
      .then((r) => r.data),

  upload: (bizType: string, bizId: string, file: File) => {
    const form = new FormData()
    form.append('bizType', bizType)
    form.append('bizId', bizId)
    form.append('file', file)
    return http
      .post<UploadResult>('/attachments', form, {
        headers: { 'Content-Type': 'multipart/form-data' }
      })
      .then((r) => r.data)
  },

  remove: (attachmentId: number) => http.delete(`/attachments/${attachmentId}`),

  /**
   * The download endpoint needs the Authorization header, so a plain link will
   * not do: fetch the bytes and hand the browser a blob URL instead.
   */
  /**
   * Opens the file in a new tab, for the formats the browser renders itself.
   * The download endpoint needs the Authorization header, so a plain link would
   * arrive unauthenticated: the bytes are fetched and handed over as a blob URL.
   * The URL is deliberately not revoked -- the new tab owns it until it closes.
   */
  openInNewTab: async (attachmentId: number) => {
    const response = await http.get(`/attachments/${attachmentId}/download`, {
      responseType: 'blob'
    })
    window.open(window.URL.createObjectURL(response.data as Blob), '_blank')
  },

  downloadAndSave: async (attachmentId: number, fileName: string) => {
    const response = await http.get(`/attachments/${attachmentId}/download`, {
      responseType: 'blob'
    })
    const url = window.URL.createObjectURL(response.data as Blob)
    const link = document.createElement('a')
    link.href = url
    link.download = fileName
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)
  }
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}
