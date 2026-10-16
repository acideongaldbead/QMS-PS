import http from './http'

/**
 * Maintenance API for the platform's own reference data (PS-109 / PS-036).
 *
 * Separate from api/masterData.ts on purpose: that file feeds every picker and is
 * read-only, this one is the administration side under /manage. Types are written
 * by hand, like every other api/*.ts.
 */

/** One maintainable dictionary type, for the left-hand list. */
export interface DictionaryType {
  mdType: string
  total: number
  active: number
  /** False for the priority list, whose target days live in the server config. */
  editable: boolean
}

export interface DictionaryEntry {
  id: number
  mdType: string
  code: string
  nameCn: string
  nameEn?: string | null
  sortOrder?: number | null
  active: boolean
  sourceSystem: string
}

export interface DictionaryCreateRequest {
  code: string
  nameCn: string
  nameEn?: string | null
  sortOrder?: number | null
}

/** The code carries the level, so only these three move. */
export interface DictionaryUpdateRequest {
  nameCn: string
  nameEn?: string | null
  sortOrder?: number | null
}

export interface FailureTypeNode {
  id: number
  code: string
  name: string
  levelNo: number
  active: boolean
  parentId: number | null
  children: FailureTypeNode[]
}

export interface FailureTypeCreateRequest {
  /** Null (or omitted) creates a level-1 node. */
  parentCode?: string | null
  code: string
  name: string
}

export interface FailureTypeUpdateRequest {
  name: string
}

const BASE = '/master-data/manage'
const segment = (value: string) => encodeURIComponent(value)

export const masterDataAdminApi = {
  // ---- dictionary --------------------------------------------------------
  dictionaryTypes: () => http.get<DictionaryType[]>(`${BASE}/dictionary-types`).then((r) => r.data),

  items: (mdType: string) =>
    http.get<DictionaryEntry[]>(`${BASE}/dictionary/${segment(mdType)}`).then((r) => r.data),

  createItem: (mdType: string, body: DictionaryCreateRequest) =>
    http.post(`${BASE}/dictionary/${segment(mdType)}`, body).then(() => undefined),

  updateItem: (mdType: string, code: string, body: DictionaryUpdateRequest) =>
    http.put(`${BASE}/dictionary/${segment(mdType)}/${segment(code)}`, body).then(() => undefined),

  activateItem: (mdType: string, code: string) =>
    http.post(`${BASE}/dictionary/${segment(mdType)}/${segment(code)}/activate`).then(() => undefined),

  deactivateItem: (mdType: string, code: string) =>
    http.post(`${BASE}/dictionary/${segment(mdType)}/${segment(code)}/deactivate`).then(() => undefined),

  deleteItem: (mdType: string, code: string) =>
    http.delete(`${BASE}/dictionary/${segment(mdType)}/${segment(code)}`).then(() => undefined),

  // ---- failure type ------------------------------------------------------
  failureTypeTree: () => http.get<FailureTypeNode[]>(`${BASE}/failure-types/tree`).then((r) => r.data),

  createFailureType: (body: FailureTypeCreateRequest) =>
    http.post(`${BASE}/failure-types`, body).then(() => undefined),

  renameFailureType: (code: string, body: FailureTypeUpdateRequest) =>
    http.put(`${BASE}/failure-types/${segment(code)}`, body).then(() => undefined),

  activateFailureType: (code: string) =>
    http.post(`${BASE}/failure-types/${segment(code)}/activate`).then(() => undefined),

  deactivateFailureType: (code: string) =>
    http.post(`${BASE}/failure-types/${segment(code)}/deactivate`).then(() => undefined),

  deleteFailureType: (code: string) =>
    http.delete(`${BASE}/failure-types/${segment(code)}`).then(() => undefined)
}
