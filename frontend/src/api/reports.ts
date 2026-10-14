import http from './http'
import type { ComplaintDetail } from './complaints'
import type { ContainmentSummary } from './containment'
import type { TaskView } from './verification'
import type { RootCauseView } from './rootCause'
import type { CorrectiveActionView, PreventionView } from './actions'

/** The newest approval task of a report; absent until it has been submitted. */
export interface ApprovalView {
  approvalId: string
  approverId?: string | null
  approverName?: string | null
  statusCode: string
  statusName?: string | null
  comment?: string | null
  pushedAt?: string | null
  completedAt?: string | null
}

export interface ReportView {
  reportId: string
  complaintId: string
  reportType: string
  reportTypeName?: string | null
  versionNo: string
  currentStep?: string | null
  approvalStatus: string
  approvalStatusName?: string | null
  reportStartDate?: string | null
  reportTargetDate?: string | null
  reportCloseDate?: string | null
  generatedAt?: string | null
  templateCode?: string | null
  approval?: ApprovalView | null
}

/** An employee who may approve reports. */
export interface Approver {
  employeeId: string
  name: string
}

export interface TeamMemberView {
  functionName?: string | null
  memberName?: string | null
  jobTitle?: string | null
  employeeId?: string | null
}

export interface DistributionView {
  logId: number
  senderName?: string | null
  recipient: string
  ccList?: string | null
  sentAt?: string | null
  attachmentVersion?: string | null
  channel?: string | null
}

/** The assembled report. The per-stage blocks reuse the detail screens' types. */
export interface ReportContent {
  report: ReportView
  complaint: ComplaintDetail
  team: TeamMemberView[]
  containment: ContainmentSummary | null
  verificationTasks: TaskView[]
  rootCauses: RootCauseView[]
  correctiveActions: CorrectiveActionView[]
  preventionFiles: PreventionView[]
  distributions: DistributionView[]
}

export interface ReportSendRequest {
  recipient: string
  ccList?: string | null
  subject: string
  body: string
}

export interface ReportSendResult {
  report: ReportView
  distribution: DistributionView | null
}

export const reportsApi = {
  list: (complaintId: string) =>
    http.get<ReportView[]>(`/complaints/${complaintId}/reports`).then((r) => r.data),

  generate: (complaintId: string, reportType: string) =>
    http.post<ReportView>(`/complaints/${complaintId}/reports`, { reportType }).then((r) => r.data),

  view: (reportId: string) => http.get<ReportContent>(`/reports/${reportId}`).then((r) => r.data),

  /** Who may approve reports, for the submit dialog. */
  approvers: () => http.get<Approver[]>('/reports/approvers').then((r) => r.data),

  /** Hands a draft (or a rejected report) to an approver. */
  submit: (reportId: string, approverId: string) =>
    http.post<ReportView>(`/reports/${reportId}/submit`, { approverId }).then((r) => r.data),

  /** The approver's decision; a rejection needs a comment. */
  approve: (reportId: string, approved: boolean, comment?: string) =>
    http
      .post<ReportView>(`/reports/${reportId}/approve`, { approved, comment })
      .then((r) => r.data),

  send: (reportId: string, payload: ReportSendRequest) =>
    http.post<ReportSendResult>(`/reports/${reportId}/send`, payload).then((r) => r.data),

  /**
   * The export endpoints need the Authorization header, so fetch the bytes and
   * hand the browser a blob URL (same approach as the attachment download).
   */
  exportDocx: async (reportId: string, fileName: string) =>
    saveBlob(await fetchReportFile(reportId, 'export.docx'), fileName),

  /** The read-only copy of the same report. */
  exportPdf: async (reportId: string, fileName: string) =>
    saveBlob(await fetchReportFile(reportId, 'export.pdf'), fileName)
}

async function fetchReportFile(reportId: string, path: string): Promise<Blob> {
  const response = await http.get(`/reports/${reportId}/${path}`, { responseType: 'blob' })
  return response.data as Blob
}

function saveBlob(blob: Blob, fileName: string) {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  window.URL.revokeObjectURL(url)
}
