import http from './http'

export interface CorrectiveActionRequest {
  rootCauseId: string
  nexSampleNumber?: string | null
  customerSampleId?: string | null
  plannedActionDesc: string
  ownerId: string
  targetDate: string
  statusCode?: string | null
}

export interface CorrectiveActionView {
  correctiveActionId: string
  rootCauseId: string
  rootCauseSummary?: string | null
  complaintId: string
  nexSampleNumber?: string | null
  customerSampleId?: string | null
  plannedActionDesc: string
  ownerId: string
  ownerName?: string | null
  targetDate: string
  statusCode: string
  statusName?: string | null
  latestVerificationId?: number | null
  actualCompletionDate?: string | null
  isEffective?: boolean | null
  verificationResult?: string | null
  verifiedAt?: string | null
  verifiedByName?: string | null
  verificationCount: number
}

export interface VerificationRequest {
  actualCompletionDate?: string | null
  verificationResult?: string | null
  /** null records progress without judging effectiveness yet. */
  isEffective?: boolean | null
}

export interface VerificationView {
  verificationId: number
  correctiveActionId: string
  actualCompletionDate?: string | null
  verificationResult?: string | null
  isEffective?: boolean | null
  verifiedBy?: string | null
  verifiedByName?: string | null
  verifiedAt?: string | null
}

export interface CorrectiveActionDetail {
  action: CorrectiveActionView
  verifications: VerificationView[]
}

export interface PreventionRequest {
  fileTypeCode: string
  nexSampleNumber?: string | null
  customerSampleId?: string | null
  controlProgram?: string | null
  referenceNumber?: string | null
  statusCode?: string | null
}

export interface PreventionView {
  updateId: number
  complaintId: string
  nexSampleNumber?: string | null
  customerSampleId?: string | null
  fileTypeCode: string
  fileTypeName?: string | null
  controlProgram?: string | null
  referenceNumber?: string | null
  statusCode: string
  statusName?: string | null
  createdBy?: string | null
  createdByName?: string | null
  createdAt?: string | null
}

/** Matches the CORR_* rows seeded with entity_name='CorrectiveAction'. */
export const CORRECTIVE_STATUSES = [
  { code: 'CORR_TODO', label: '待处理' },
  { code: 'CORR_DOING', label: '进行中' },
  { code: 'CORR_DONE', label: '已实施' },
  { code: 'CORR_VERIFIED', label: '已验证' },
  { code: 'CORR_FAILED', label: '验证不通过' }
]

/** Matches the PREV_* rows seeded with entity_name='PreventionFileUpdate'. */
export const PREVENTION_STATUSES = [
  { code: 'PREV_TODO', label: '待更新' },
  { code: 'PREV_DOING', label: '更新中' },
  { code: 'PREV_DONE', label: '已完成' }
]

export const actionsApi = {
  listActions: (complaintId: string) =>
    http.get<CorrectiveActionView[]>(`/complaints/${complaintId}/corrective-actions`).then((r) => r.data),

  actionDetail: (actionId: string) =>
    http.get<CorrectiveActionDetail>(`/corrective-actions/${actionId}`).then((r) => r.data),

  createAction: (complaintId: string, payload: CorrectiveActionRequest) =>
    http.post<CorrectiveActionDetail>(`/complaints/${complaintId}/corrective-actions`, payload).then((r) => r.data),

  updateAction: (actionId: string, payload: CorrectiveActionRequest) =>
    http.put<CorrectiveActionDetail>(`/corrective-actions/${actionId}`, payload).then((r) => r.data),

  removeAction: (actionId: string) => http.delete(`/corrective-actions/${actionId}`),

  addVerification: (actionId: string, payload: VerificationRequest) =>
    http.post<CorrectiveActionDetail>(`/corrective-actions/${actionId}/verifications`, payload).then((r) => r.data),

  removeVerification: (actionId: string, verificationId: number) =>
    http.delete<CorrectiveActionDetail>(`/corrective-actions/${actionId}/verifications/${verificationId}`).then((r) => r.data),

  listPrevention: (complaintId: string) =>
    http.get<PreventionView[]>(`/complaints/${complaintId}/prevention-files`).then((r) => r.data),

  createPrevention: (complaintId: string, payload: PreventionRequest) =>
    http.post<PreventionView[]>(`/complaints/${complaintId}/prevention-files`, payload).then((r) => r.data),

  updatePrevention: (updateId: number, payload: PreventionRequest) =>
    http.put<PreventionView[]>(`/prevention-files/${updateId}`, payload).then((r) => r.data),

  removePrevention: (updateId: number) =>
    http.delete<PreventionView[]>(`/prevention-files/${updateId}`).then((r) => r.data)
}
