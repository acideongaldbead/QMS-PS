import http from './http'

export interface TaskRequest {
  sampleId?: string | null
  taskOwnerId: string
  plannedStartDate?: string | null
  targetCompletionDate: string
  taskStatus?: string | null
  creationMode?: string | null
}

export interface TaskView {
  taskId: string
  complaintId: string
  sampleId?: string | null
  sampleCustomerSampleId?: string | null
  taskOwnerId: string
  taskOwnerName?: string | null
  plannedStartDate?: string | null
  targetCompletionDate: string
  creationMode?: string | null
  taskStatus: string
  taskStatusName?: string | null
  completedAt?: string | null
  resultCount: number
  targetWarning?: string | null
}

export interface ResultRequest {
  testItem: string
  failureTypeL1Code?: string | null
  failureTypeL2Code?: string | null
  failureTypeL3Code?: string | null
  resultConclusion?: string | null
}

export interface ResultView {
  resultId: number
  taskId: string
  testItem: string
  failureTypeL1Code?: string | null
  failureTypeL1Name?: string | null
  failureTypeL2Code?: string | null
  failureTypeL2Name?: string | null
  failureTypeL3Code?: string | null
  failureTypeL3Name?: string | null
  resultConclusion?: string | null
  entryMode?: string | null
  recordedBy?: string | null
  recordedByName?: string | null
  recordedAt?: string | null
}

export interface TaskDetail {
  task: TaskView
  results: ResultView[]
}

export interface ValidityRequest {
  valid: boolean
  reasonCode?: string | null
  conclusion?: string | null
}

export interface ValidityResult {
  complaintId: string
  valid: boolean
  statusCode: string
  currentStage: string
  closeDate?: string | null
  closeReasonCode?: string | null
}

/** Matches the rows seeded with entity_name='VerificationTask'. */
export const TASK_STATUSES = [
  { code: 'VERIF_TODO', label: '待排期' },
  { code: 'VERIF_SCHEDULED', label: '已排期' },
  { code: 'VERIF_DOING', label: '验证中' },
  { code: 'VERIF_DONE', label: '已完成' },
  { code: 'VERIF_CANCELLED', label: '已取消' }
]

export const verificationApi = {
  listTasks: (complaintId: string) =>
    http.get<TaskView[]>(`/complaints/${complaintId}/verification-tasks`).then((r) => r.data),

  taskDetail: (taskId: string) =>
    http.get<TaskDetail>(`/verification-tasks/${taskId}`).then((r) => r.data),

  createTask: (complaintId: string, payload: TaskRequest) =>
    http.post<TaskDetail>(`/complaints/${complaintId}/verification-tasks`, payload).then((r) => r.data),

  updateTask: (taskId: string, payload: TaskRequest) =>
    http.put<TaskDetail>(`/verification-tasks/${taskId}`, payload).then((r) => r.data),

  removeTask: (taskId: string) => http.delete(`/verification-tasks/${taskId}`),

  addResult: (taskId: string, payload: ResultRequest) =>
    http.post<TaskDetail>(`/verification-tasks/${taskId}/results`, payload).then((r) => r.data),

  addBatchResults: (taskId: string, payload: ResultRequest[]) =>
    http.post<TaskDetail>(`/verification-tasks/${taskId}/results/batch`, payload).then((r) => r.data),

  removeResult: (taskId: string, resultId: number) =>
    http.delete<TaskDetail>(`/verification-tasks/${taskId}/results/${resultId}`).then((r) => r.data),

  setValidity: (complaintId: string, payload: ValidityRequest) =>
    http.post<ValidityResult>(`/complaints/${complaintId}/validity`, payload).then((r) => r.data)
}
