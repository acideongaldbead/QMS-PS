import type {
  CreateComplaintRequest,
  FailureDescriptionForm,
  ProductForm,
  SampleForm
} from '@/api/complaints'

export function emptySample(): SampleForm {
  return {
    customerSampleId: null,
    champId: null,
    sampleQuantity: null,
    uom: 'PCS',
    description: null,
    productMarking: null,
    applicationArea: null,
    rejectConfirmed: null,
    conclusion: null,
    failureTypeL1Code: null,
    failureTypeL2Code: null,
    failureTypeL3Code: null
  }
}

export function emptyProduct(): ProductForm {
  return {
    materialCode: null,
    productTypeCode: '',
    packingTypeCode: '',
    businessGroup: null,
    businessUnit: null,
    nc9: null,
    mag: null,
    customerPartNo: null,
    tg4: null,
    tg5: null,
    tg6: null,
    productStatus: null,
    isProtected: null
  }
}

export function emptyFailureDescription(): FailureDescriptionForm {
  return {
    customerFailureDescription: null,
    customerFailureModeCode: '',
    d0SymptomsDescription: null,
    comment: null,
    quantityFailing: null,
    quantityFailingUom: 'PCS',
    qualityReturned: null,
    qualityReturnedUom: 'PCS',
    customerPo: null,
    salesOrder: null,
    supplierInvoiceNumber: null,
    shippedDirectly: null,
    directCommunication: null,
    receivedApprPack: null,
    analysisConclusion: null
  }
}

/**
 * A blank registration. Required fields start empty so the browser-side rules and
 * the server-side rules agree on what "missing" means.
 */
export function emptyComplaintForm(): CreateComplaintRequest {
  return {
    header: {
      complaintTypeCode: '',
      priorityCode: '',
      failureLocationCode: '',
      complaintOwnerId: '',
      coordinatorId: '',
      verificationOwnerId: null,
      reportOwnerId: null,
      customerTargetDate: '',
      startDate: null,
      targetDate: null,
      customerReferenceId: null
    },
    qualityPartner: {
      qualityPartnerCode: '',
      application: 'Yes',
      contactPersonId: '',
      subSegmentCode: '',
      shipToSoldToCode: null,
      hsCode: null,
      endCustomer: null,
      eccn: null
    },
    product: emptyProduct(),
    failureDescription: emptyFailureDescription(),
    samples: [emptySample()]
  }
}

export const STEP_TITLES = [
  '投诉头信息',
  '质量合作伙伴',
  '产品信息',
  '失效描述',
  '客诉样品'
] as const

export const UOM_OPTIONS = ['PCS', 'SET', 'KG', 'M', 'LOT']
