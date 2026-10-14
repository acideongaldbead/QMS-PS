import http from './http'

export interface ActionRequest {
  nexSampleNumber?: string | null
  customerSampleNumber?: string | null
  plannedAction: string
  ownerId: string
  plannedCompletionDate?: string | null
  completedDate?: string | null
  statusCode?: string | null
  result?: string | null
}

export interface ActionView {
  actionId: string
  complaintId: string
  nexSampleNumber?: string | null
  customerSampleNumber?: string | null
  plannedAction: string
  ownerId: string
  ownerName?: string | null
  plannedCompletionDate?: string | null
  completedDate?: string | null
  statusCode: string
  statusName?: string | null
  result?: string | null
  createdBy?: string | null
  createdByName?: string | null
  createdAt?: string | null
  /** Set when the action finished before it was planned to. */
  completionWarning?: string | null
}

export interface ContainmentSummary {
  /** null until the PS-039 decision has been made. */
  required: boolean | null
  decisionNote?: string | null
  actions: ActionView[]
  complaintClosed: boolean
}

/** Matches the CONTAIN_* rows seeded with entity_name='ContainmentAction'. */
export const CONTAINMENT_STATUSES = [
  { code: 'CONTAIN_TODO', label: '待处理' },
  { code: 'CONTAIN_DOING', label: '进行中' },
  { code: 'CONTAIN_DONE', label: '已完成' },
  { code: 'CONTAIN_CANCELLED', label: '已取消' }
]

export const containmentApi = {
  summary: (complaintId: string) =>
    http.get<ContainmentSummary>(`/complaints/${complaintId}/containment`).then((r) => r.data),

  decide: (complaintId: string, required: boolean, note?: string | null) =>
    http
      .post<ContainmentSummary>(`/complaints/${complaintId}/containment/decision`, { required, note })
      .then((r) => r.data),

  createAction: (complaintId: string, payload: ActionRequest) =>
    http
      .post<ContainmentSummary>(`/complaints/${complaintId}/containment/actions`, payload)
      .then((r) => r.data),

  updateAction: (actionId: string, payload: ActionRequest) =>
    http.put<ContainmentSummary>(`/containment-actions/${actionId}`, payload).then((r) => r.data),

  removeAction: (actionId: string) =>
    http.delete<ContainmentSummary>(`/containment-actions/${actionId}`).then((r) => r.data)
}
