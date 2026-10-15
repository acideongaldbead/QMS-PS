import http from './http'

/**
 * The announcement management screen (requirement 3.0 / PS-003).
 *
 * The home page keeps reading through homeApi.announcements; this is the
 * administrator's side: every status, plus create / edit / publish / retire /
 * delete. `content` is sanitised HTML on the server, so the home drawer renders
 * it with v-html.
 */
export interface AnnouncementManage {
  announcementId: number
  title: string
  content: string
  publishStatus: string
  publishedAt?: string | null
  publishedByName?: string | null
  updatedAt?: string | null
  updatedByName?: string | null
}

/** Create and edit share one shape; the id travels in the path. */
export interface AnnouncementSaveRequest {
  title: string
  content: string
  /** Wall-clock time; null lets publish stamp the current time. */
  publishedAt?: string | null
}

export const announcementApi = {
  /** Every announcement, any status; `status` narrows to one. */
  list: (status?: string) =>
    http
      .get<AnnouncementManage[]>('/announcements/manage', { params: { status } })
      .then((r) => r.data),

  get: (announcementId: number) =>
    http.get<AnnouncementManage>(`/announcements/manage/${announcementId}`).then((r) => r.data),

  create: (body: AnnouncementSaveRequest) =>
    http.post<AnnouncementManage>('/announcements/manage', body).then((r) => r.data),

  update: (announcementId: number, body: AnnouncementSaveRequest) =>
    http.put<AnnouncementManage>(`/announcements/manage/${announcementId}`, body).then((r) => r.data),

  publish: (announcementId: number) =>
    http.post<AnnouncementManage>(`/announcements/manage/${announcementId}/publish`).then((r) => r.data),

  retire: (announcementId: number) =>
    http.post<AnnouncementManage>(`/announcements/manage/${announcementId}/retire`).then((r) => r.data),

  remove: (announcementId: number) =>
    http.delete(`/announcements/manage/${announcementId}`).then(() => undefined)
}
