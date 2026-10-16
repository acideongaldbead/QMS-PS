import { defineStore } from 'pinia'
import {
  masterDataApi,
  type Customer,
  type DictionaryItem,
  type Employee,
  type FailureType,
  type Product
} from '@/api/masterData'
import { complaintApi } from '@/api/complaints'

/**
 * Reference data shared across screens. Loaded once per session and reused, so
 * opening a dropdown does not hit the database every time.
 *
 * Per-customer lists (contacts, ship-to plants) are NOT cached here: they depend
 * on the selected customer and are fetched on demand by the form.
 */
export const useMetaStore = defineStore('meta', {
  state: () => ({
    loaded: false,
    loading: false,
    complaintTypes: [] as DictionaryItem[],
    priorities: [] as DictionaryItem[],
    failureLocations: [] as DictionaryItem[],
    subSegments: [] as DictionaryItem[],
    productTypes: [] as DictionaryItem[],
    packingTypes: [] as DictionaryItem[],
    failureModes: [] as DictionaryItem[],
    closeReasons: [] as DictionaryItem[],
    responsibleOrgs: [] as DictionaryItem[],
    fileTypes: [] as DictionaryItem[],
    knowledgeCategories: [] as DictionaryItem[],
    employees: [] as Employee[],
    customers: [] as Customer[],
    products: [] as Product[],
    failureTypes: [] as FailureType[],
    /** priority code -> calendar days added to the start date. */
    priorityDays: {} as Record<string, number>
  }),

  getters: {
    employeeName: (s) => (id?: string | null) =>
      id ? (s.employees.find((e) => e.id === id)?.name ?? id) : ''
  },

  actions: {
    async ensureLoaded() {
      if (this.loaded || this.loading) return
      this.loading = true
      try {
        const [
          complaintTypes,
          priorities,
          failureLocations,
          subSegments,
          productTypes,
          packingTypes,
          failureModes,
          closeReasons,
          responsibleOrgs,
          fileTypes,
          knowledgeCategories,
          employees,
          customers,
          products,
          failureTypes,
          rules
        ] = await Promise.all([
          masterDataApi.dictionary('complaint_type'),
          masterDataApi.dictionary('priority'),
          masterDataApi.dictionary('failure_location'),
          masterDataApi.dictionary('sub_segment'),
          masterDataApi.dictionary('product_type'),
          masterDataApi.dictionary('packing_type'),
          masterDataApi.dictionary('failure_mode'),
          masterDataApi.dictionary('close_reason'),
          masterDataApi.dictionary('responsible_org'),
          masterDataApi.dictionary('file_type'),
          masterDataApi.dictionary('knowledge_category'),
          masterDataApi.employees(),
          masterDataApi.customers(),
          masterDataApi.products(),
          masterDataApi.failureTypeTree(),
          complaintApi.priorityRules()
        ])

        this.complaintTypes = complaintTypes
        this.priorities = priorities
        this.failureLocations = failureLocations
        this.subSegments = subSegments
        this.productTypes = productTypes
        this.packingTypes = packingTypes
        this.failureModes = failureModes
        this.closeReasons = closeReasons
        this.responsibleOrgs = responsibleOrgs
        this.fileTypes = fileTypes
        this.knowledgeCategories = knowledgeCategories
        this.employees = employees
        this.customers = customers
        this.products = products
        this.failureTypes = failureTypes

        const days: Record<string, number> = {}
        for (const rule of rules) days[rule.code] = rule.days
        this.priorityDays = days

        this.loaded = true
      } finally {
        this.loading = false
      }
    },

    /**
     * Drops the cache. Both flags have to go: ensureLoaded() bails out while
     * `loading` is true, so clearing only `loaded` would make the re-read that
     * follows a master-data change silently do nothing and leave stale data in
     * every dropdown.
     */
    reset() {
      this.loaded = false
      this.loading = false
    },

    /**
     * Re-reads every dictionary. Called after a master-data edit so the pickers,
     * the knowledge-centre sidebar and the failure-type cascade all show the new
     * values without a reload.
     */
    async refresh() {
      this.reset()
      await this.ensureLoaded()
    }
  }
})
