import http from './http'

export interface DictionaryItem {
  code: string
  nameCn: string
  nameEn?: string
  sortOrder?: number
}

export interface Option {
  code: string
  name: string
}

export interface FailureType {
  id: number
  levelNo: number
  code: string
  name: string
  parentId: number | null
  children: FailureType[]
}

export interface Customer {
  code: string
  name: string
  country?: string
  city?: string
  streetAddress?: string
}

export interface Contact {
  id: string
  name: string
  email?: string
  phone?: string
}

export interface Product {
  code: string
  description?: string
  productTypeCode?: string
  productTypeName?: string
  packingTypeCode?: string
  packingTypeName?: string
  businessGroup?: string
  businessUnit?: string
}

export interface Employee {
  id: string
  name: string
  nameEn?: string
  email?: string
  deptL1?: string
  deptL2?: string
  jobTitle?: string
}

export interface StatusCode {
  code: string
  entityName: string
  nameCn: string
  nameEn?: string
  sortOrder?: number
  isFinal?: boolean
}

export const masterDataApi = {
  dictionary: (mdType: string) =>
    http.get<DictionaryItem[]>(`/master-data/dictionary/${mdType}`).then((r) => r.data),
  failureTypeTree: () =>
    http.get<FailureType[]>('/master-data/failure-types/tree').then((r) => r.data),
  customers: (q?: string) =>
    http.get<Customer[]>('/master-data/customers', { params: { q } }).then((r) => r.data),
  shipToOf: (customerCode: string) =>
    http.get<Option[]>(`/master-data/customers/${customerCode}/ship-to`).then((r) => r.data),
  contactsOf: (customerCode: string) =>
    http.get<Contact[]>(`/master-data/customers/${customerCode}/contacts`).then((r) => r.data),
  products: (q?: string) =>
    http.get<Product[]>('/master-data/products', { params: { q } }).then((r) => r.data),
  employees: (q?: string) =>
    http.get<Employee[]>('/master-data/employees', { params: { q } }).then((r) => r.data),
  statusCodes: (entity?: string) =>
    http.get<StatusCode[]>('/master-data/status-codes', { params: { entity } }).then((r) => r.data)
}
