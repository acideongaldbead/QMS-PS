import http from './http'

/**
 * Field names mirror the backend records in ComplaintRequests so the same shape
 * is used for writing and for reading a complaint back.
 */
export interface HeaderForm {
  complaintTypeCode: string
  priorityCode: string
  failureLocationCode: string
  complaintOwnerId: string
  coordinatorId: string
  verificationOwnerId?: string | null
  reportOwnerId?: string | null
  customerTargetDate: string
  startDate?: string | null
  targetDate?: string | null
  customerReferenceId?: string | null
}

export interface QualityPartnerForm {
  qualityPartnerCode: string
  application: string
  contactPersonId: string
  hsCode?: string | null
  endCustomer?: string | null
  eccn?: string | null
  subSegmentCode: string
  shipToSoldToCode?: string | null
}

export interface ProductForm {
  materialCode?: string | null
  productTypeCode: string
  packingTypeCode: string
  businessGroup?: string | null
  businessUnit?: string | null
  nc9?: string | null
  mag?: string | null
  customerPartNo?: string | null
  tg4?: string | null
  tg5?: string | null
  tg6?: string | null
  productStatus?: string | null
  isProtected?: boolean | null
}

export interface FailureDescriptionForm {
  customerFailureDescription?: string | null
  customerFailureModeCode: string
  d0SymptomsDescription?: string | null
  comment?: string | null
  quantityFailing?: number | null
  quantityFailingUom?: string | null
  qualityReturned?: number | null
  qualityReturnedUom?: string | null
  customerPo?: string | null
  salesOrder?: string | null
  supplierInvoiceNumber?: string | null
  shippedDirectly?: boolean | null
  directCommunication?: string | null
  receivedApprPack?: string | null
  analysisConclusion?: string | null
}

export interface SampleForm {
  customerSampleId?: string | null
  champId?: string | null
  sampleQuantity?: number | null
  uom?: string | null
  description?: string | null
  productMarking?: string | null
  applicationArea?: string | null
  rejectConfirmed?: boolean | null
  conclusion?: string | null
  failureTypeL1Code?: string | null
  failureTypeL2Code?: string | null
  failureTypeL3Code?: string | null
}

export interface CreateComplaintRequest {
  header: HeaderForm
  qualityPartner: QualityPartnerForm
  product: ProductForm
  failureDescription: FailureDescriptionForm
  samples: SampleForm[]
}

export interface CreatedComplaint {
  complaintId: string
  statusCode: string
  currentStage: string
  startDate: string
  targetDate: string
  customerTargetDate: string
  sampleIds: string[]
}

export interface PriorityRule {
  code: string
  days: number
}

export interface ComplaintLabels {
  customerName?: string | null
  contactName?: string | null
  contactEmail?: string | null
  shipToName?: string | null
  productDescription?: string | null
  ownerName?: string | null
  coordinatorName?: string | null
  verificationOwnerName?: string | null
  reportOwnerName?: string | null
  createdByName?: string | null
  complaintTypeName?: string | null
  priorityName?: string | null
  failureLocationName?: string | null
  subSegmentName?: string | null
  customerFailureModeName?: string | null
  statusName?: string | null
}

export interface ComplaintDetail {
  complaintId: string
  statusCode: string
  currentStage: string
  processType: string
  startDate?: string | null
  targetDate?: string | null
  customerTargetDate?: string | null
  closeDate?: string | null
  isValid?: boolean | null
  closeReasonCode?: string | null
  customerReferenceId?: string | null
  createdBy?: string | null
  createdAt?: string | null
  overdueDays: number
  header: HeaderForm
  qualityPartner: QualityPartnerForm | null
  product: ProductForm | null
  failureDescription: FailureDescriptionForm | null
  samples: { sampleId: string; value: SampleForm }[]
  labels: ComplaintLabels | null
}

export interface LedgerQuery {
  scope?: 'mine' | 'all'
  q?: string
  status?: string
  priority?: string
  customer?: string
  complaintType?: string
  owner?: string
  product?: string
  startFrom?: string
  startTo?: string
  targetFrom?: string
  targetTo?: string
  overdue?: boolean
  open?: boolean
  valid?: boolean
  page?: number
  size?: number
  sort?: string
  order?: 'asc' | 'desc'
}

/** One complaint ledger row. Dates arrive as ISO yyyy-MM-dd strings. */
export interface LedgerRow {
  complaintId: string
  statusCode: string
  statusName?: string | null
  currentStage: string
  priorityCode: string
  priorityName?: string | null
  customerName?: string | null
  productCode?: string | null
  /** The product type dictionary name shown in the ledger's 产品类型 column. */
  productTypeName?: string | null
  startDate?: string | null
  targetDate?: string | null
  closeDate?: string | null
  closeReasonCode?: string | null
  processingDays?: number | null
  ownerId?: string | null
  ownerName?: string | null
  customerReferenceId?: string | null
  overdueDays: number
  mine: boolean
}

export interface LedgerPage {
  items: LedgerRow[]
  total: number
  page: number
  size: number
  /** Unfiltered counters behind the two tabs. */
  mineTotal: number
  allTotal: number
}

/** One line of the complaint's process and communication history. */
export interface LogEntry {
  at?: string | null
  kind: 'AUDIT' | 'COMMUNICATION'
  actorName?: string | null
  actionLabel: string
  detail?: string | null
  /** Timeline dot tone: 'done' | 'warn' | '' (neutral). */
  tone: string
}

export const complaintApi = {
  create: (payload: CreateComplaintRequest) =>
    http.post<CreatedComplaint>('/complaints', payload).then((r) => r.data),
  detail: (complaintId: string) =>
    http.get<ComplaintDetail>(`/complaints/${complaintId}`).then((r) => r.data),
  /** The 沟通与流程日志 tab: process trail plus sent-report log, newest first. */
  logs: (complaintId: string) =>
    http.get<LogEntry[]>(`/complaints/${complaintId}/logs`).then((r) => r.data),
  /** The ledger, paged and filtered server side (requirement 3.1.1). */
  ledger: (params: LedgerQuery) => http.get<LedgerPage>('/complaints', { params }).then((r) => r.data),
  /** The workbook. `ids` is a comma-separated selection, sent only when rows are ticked. */
  exportLedger: (params: LedgerQuery & { ids?: string }) =>
    http.get('/complaints/export', { params, responseType: 'blob' }).then((r) => r.data as Blob),
  priorityRules: () => http.get<PriorityRule[]>('/complaints/priority-rules').then((r) => r.data),

  /** Samples added or corrected after registration (requirement 3.1.6). */
  addSample: (complaintId: string, form: SampleForm) =>
    http.post<{ sampleId: string }>(`/complaints/${complaintId}/samples`, form).then((r) => r.data),
  updateSample: (complaintId: string, sampleId: string, form: SampleForm) =>
    http.put(`/complaints/${complaintId}/samples/${sampleId}`, form),
  removeSample: (complaintId: string, sampleId: string) =>
    http.delete(`/complaints/${complaintId}/samples/${sampleId}`)
}
