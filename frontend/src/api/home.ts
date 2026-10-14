import http from './http'
import type { LedgerRow } from './complaints'

/** One thing waiting for the current user (requirement 3.0's 我的待办). */
export interface TodoItem {
  todoId: string
  /** Stable key, e.g. VERIFICATION. */
  type: string
  /** Group heading, resolved server side. */
  typeLabel: string
  title: string
  complaintId: string
  /** Which tab of the complaint detail this entry opens. */
  tab: string
  dueDate?: string | null
  overdueDays: number
  urgent: boolean
  statusText?: string | null
}

export interface HomeStats {
  todoCount: number
  todoTypeCount: number
  overdueTaskCount: number
  pendingApprovalCount: number
  myComplaintCount: number
}

export interface HomeOverview {
  stats: HomeStats
  todos: TodoItem[]
  /** Total before the display cap. */
  todoTotal: number
  /** Reuses the ledger row shape, so "overdue" means the same thing on both screens. */
  overdueComplaints: LedgerRow[]
  overdueComplaintTotal: number
}

export interface Announcement {
  announcementId: number
  title: string
  content: string
  publishedAt?: string | null
  publishedByName?: string | null
  /** True while this reader has never opened it — the NEW badge. */
  isNew: boolean
}

export const homeApi = {
  overview: () => http.get<HomeOverview>('/home/overview').then((r) => r.data),
  announcements: (limit?: number) =>
    http.get<Announcement[]>('/announcements', { params: { limit } }).then((r) => r.data),
  /** Records that this user opened the announcement, which clears its NEW badge. */
  markAnnouncementRead: (announcementId: number) =>
    http.post(`/announcements/${announcementId}/read`).then(() => undefined)
}
