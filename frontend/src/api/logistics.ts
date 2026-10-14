import http from './http'

export interface ShipmentView {
  shipmentId: string
  complaintId: string
  senderId: string
  senderName?: string | null
  receiverId: string
  receiverName?: string | null
  shipmentNo?: string | null
  shipmentStatus?: string | null
  shipmentStatusName?: string | null
  quantityPartsShipped: number
  application?: string | null
  startDate?: string | null
  carrierName: string
  carrierTrackingNumber?: string | null
  targetDate?: string | null
  closeDate?: string | null
  comments?: string | null
  createdBy?: string | null
  createdByName?: string | null
  createdAt?: string | null
  sampleCount: number
  overdueDays: number
}

export interface ShipmentRequest {
  senderId: string
  receiverId: string
  shipmentNo?: string | null
  shipmentStatus?: string | null
  quantityPartsShipped: number | null
  application?: string | null
  startDate?: string | null
  carrierName: string
  carrierTrackingNumber?: string | null
  targetDate?: string | null
  closeDate?: string | null
  comments?: string | null
}

export interface ShipmentSampleRequest {
  sampleId: string
  description?: string | null
  dateCode?: string | null
  dbId?: string | null
  qty?: number | null
  uom?: string | null
  customerSampleId?: string | null
  assemblyCenter?: string | null
  testCenter?: string | null
  numOfDies?: number | null
}

export interface ShipmentSampleView extends ShipmentSampleRequest {
  shipmentSampleId: number
  shipmentId: string
  sampleCustomerSampleId?: string | null
  failureTypeName?: string | null
}

export interface SamplePoolItem {
  sampleId: string
  customerSampleId?: string | null
  champId?: string | null
  description?: string | null
  quantity?: number | null
  uom?: string | null
  rejectConfirmed?: boolean | null
  failureTypeName?: string | null
  inThisShipment: boolean
}

export interface ShipmentDetail {
  shipment: ShipmentView
  samples: ShipmentSampleView[]
  availableSamples: SamplePoolItem[]
}

/** Sample lifecycle codes, matching the rows seeded with entity_name='Shipment'. */
export const SHIPMENT_STATUSES = [
  { code: 'SHIPMENT_PREPARING', label: '备货中' },
  { code: 'SHIPMENT_IN_TRANSIT', label: '在途' },
  { code: 'SHIPMENT_RECEIVED', label: '已签收' },
  { code: 'SHIPMENT_CLOSED', label: '已关闭' }
]

export const logisticsApi = {
  listShipments: (complaintId: string) =>
    http.get<ShipmentView[]>(`/complaints/${complaintId}/shipments`).then((r) => r.data),

  shipmentDetail: (shipmentId: string) =>
    http.get<ShipmentDetail>(`/shipments/${shipmentId}`).then((r) => r.data),

  createShipment: (complaintId: string, payload: ShipmentRequest) =>
    http.post<ShipmentDetail>(`/complaints/${complaintId}/shipments`, payload).then((r) => r.data),

  updateShipment: (shipmentId: string, payload: ShipmentRequest) =>
    http.put<ShipmentDetail>(`/shipments/${shipmentId}`, payload).then((r) => r.data),

  removeShipment: (shipmentId: string) => http.delete(`/shipments/${shipmentId}`),

  addSamples: (shipmentId: string, payload: ShipmentSampleRequest[]) =>
    http.post<ShipmentDetail>(`/shipments/${shipmentId}/samples`, payload).then((r) => r.data),

  removeSample: (shipmentId: string, sampleId: string) =>
    http
      .delete<ShipmentDetail>(`/shipments/${shipmentId}/samples/${sampleId}`)
      .then((r) => r.data)
}
