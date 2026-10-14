import http from './http'

export interface RootCauseRequest {
  rootCauseDesc: string
  rootCauseSummary?: string | null
  riskAssessment?: string | null
  /** INTERNAL or EXTERNAL. */
  responsibleOrgType?: string | null
  responsibleOrgCode?: string | null
  statusCode?: string | null
}

export interface TransferRequest {
  transferredToId: string
  responsibleOrgType?: string | null
  responsibleOrgCode?: string | null
  note?: string | null
}

export interface RootCauseView {
  rootCauseId: string
  complaintId: string
  rootCauseDesc: string
  rootCauseSummary?: string | null
  riskAssessment?: string | null
  responsibleOrgType?: string | null
  responsibleOrgCode?: string | null
  responsibleOrgName?: string | null
  transferredToId?: string | null
  transferredToName?: string | null
  transferredAt?: string | null
  statusCode: string
  statusName?: string | null
  createdBy?: string | null
  createdByName?: string | null
  createdAt?: string | null
  whyVersionCount: number
  fishboneVersionCount: number
}

export interface AnalysisView {
  analysisId: number
  rootCauseId: string
  analysisType: string
  contentJson: string
  versionNo: number
  createdBy?: string | null
  createdByName?: string | null
  createdAt?: string | null
}

export interface RootCauseDetail {
  rootCause: RootCauseView
  whyAnalysis: AnalysisView | null
  fishbone: AnalysisView | null
}

/** Matches the ROOTCAUSE_* rows seeded with entity_name='RootCause'. */
export const ROOT_CAUSE_STATUSES = [
  { code: 'ROOTCAUSE_TODO', label: '待分析' },
  { code: 'ROOTCAUSE_DOING', label: '分析中' },
  { code: 'ROOTCAUSE_DONE', label: '已完成' }
]

export const ORG_TYPES = [
  { code: 'INTERNAL', label: '内部' },
  { code: 'EXTERNAL', label: '外部根因组织' }
]

export const ANALYSIS_TYPE = {
  WHY: '3x5WHY',
  FISHBONE: 'FISHBONE'
} as const

export const rootCauseApi = {
  list: (complaintId: string) =>
    http.get<RootCauseView[]>(`/complaints/${complaintId}/root-causes`).then((r) => r.data),

  detail: (rootCauseId: string) =>
    http.get<RootCauseDetail>(`/root-causes/${rootCauseId}`).then((r) => r.data),

  create: (complaintId: string, payload: RootCauseRequest) =>
    http.post<RootCauseDetail>(`/complaints/${complaintId}/root-causes`, payload).then((r) => r.data),

  update: (rootCauseId: string, payload: RootCauseRequest) =>
    http.put<RootCauseDetail>(`/root-causes/${rootCauseId}`, payload).then((r) => r.data),

  remove: (rootCauseId: string) => http.delete(`/root-causes/${rootCauseId}`),

  transfer: (rootCauseId: string, payload: TransferRequest) =>
    http.post<RootCauseDetail>(`/root-causes/${rootCauseId}/transfer`, payload).then((r) => r.data),

  saveAnalysis: (rootCauseId: string, analysisType: string, contentJson: string) =>
    http
      .post<RootCauseDetail>(`/root-causes/${rootCauseId}/analysis`, { analysisType, contentJson })
      .then((r) => r.data),

  versions: (rootCauseId: string, analysisType: string) =>
    http
      .get<AnalysisView[]>(`/root-causes/${rootCauseId}/analysis/${analysisType}/versions`)
      .then((r) => r.data)
}
