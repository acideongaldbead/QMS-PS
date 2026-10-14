import http from './http'

/**
 * The knowledge centre (requirement 3.11): process documents, analysis
 * templates, training materials and user manuals.
 *
 * The document file itself lives in the shared attachment table under
 * bizType 'KnowledgeArticle'; the list carries the newest file's name, size,
 * type and id so a row can show and open it without a second request.
 */
export interface KnowledgeArticle {
  articleId: number
  docCode?: string | null
  title: string
  titleEn?: string | null
  /** master_data_item code of type knowledge_category. */
  category: string
  /** Category names resolved server side; pick by the current language. */
  categoryName?: string | null
  categoryNameEn?: string | null
  version?: string | null
  summary?: string | null
  content?: string | null
  maintainerName?: string | null
  updatedAt?: string | null
  /** The newest uploaded file, or null when the entry has none yet. */
  latestAttachmentId?: number | null
  latestFileName?: string | null
  latestFileSize?: number | null
  latestFileType?: string | null
}

/** Create and edit share one shape; the article id travels in the path. */
export interface KnowledgeSaveRequest {
  title: string
  titleEn?: string | null
  category: string
  docCode?: string | null
  version?: string | null
  summary?: string | null
  content?: string | null
}

export interface KnowledgeCategoryCount {
  category: string
  total: number
}

export interface KnowledgeSummary {
  total: number
  /** Only categories that hold documents; the sidebar fills the gaps with the dictionary. */
  categories: KnowledgeCategoryCount[]
}

export const knowledgeApi = {
  list: (params: { category?: string; keyword?: string }) =>
    http.get<KnowledgeArticle[]>('/knowledge/articles', { params }).then((r) => r.data),

  summary: () => http.get<KnowledgeSummary>('/knowledge/summary').then((r) => r.data),

  get: (articleId: number) =>
    http.get<KnowledgeArticle>(`/knowledge/articles/${articleId}`).then((r) => r.data),

  create: (body: KnowledgeSaveRequest) =>
    http.post<KnowledgeArticle>('/knowledge/articles', body).then((r) => r.data),

  update: (articleId: number, body: KnowledgeSaveRequest) =>
    http.put<KnowledgeArticle>(`/knowledge/articles/${articleId}`, body).then((r) => r.data),

  remove: (articleId: number) => http.delete(`/knowledge/articles/${articleId}`).then(() => undefined)
}
