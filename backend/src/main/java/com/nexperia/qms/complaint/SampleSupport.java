package com.nexperia.qms.complaint;

import com.nexperia.qms.complaint.dto.ComplaintRequests;

/**
 * Mapping between the sample form and the sample entity, shared by registering a
 * complaint and by editing a sample afterwards. Keeping one copy means the two
 * paths cannot drift apart.
 */
final class SampleSupport {

    private SampleSupport() {
    }

    static Sample newEntity(ComplaintRequests.Sample form, String complaintId, String sampleId) {
        Sample entity = new Sample();
        entity.setSampleId(sampleId);
        entity.setComplaintId(complaintId);
        applyFields(entity, form);
        return entity;
    }

    /** Copies the editable fields. Identity (sampleId, complaintId) is never touched. */
    static void applyFields(Sample entity, ComplaintRequests.Sample form) {
        entity.setCustomerSampleId(form.customerSampleId());
        entity.setChampId(form.champId());
        entity.setSampleQuantity(form.sampleQuantity());
        entity.setUom(form.uom());
        entity.setDescription(form.description());
        entity.setProductMarking(form.productMarking());
        entity.setApplicationArea(form.applicationArea());
        entity.setRejectConfirmed(form.rejectConfirmed());
        entity.setConclusion(form.conclusion());
        entity.setFailureTypeL1Code(form.failureTypeL1Code());
        entity.setFailureTypeL2Code(form.failureTypeL2Code());
        entity.setFailureTypeL3Code(form.failureTypeL3Code());
    }

    static ComplaintRequests.Sample toForm(Sample entity) {
        return new ComplaintRequests.Sample(
                entity.getCustomerSampleId(),
                entity.getChampId(),
                entity.getSampleQuantity(),
                entity.getUom(),
                entity.getDescription(),
                entity.getProductMarking(),
                entity.getApplicationArea(),
                entity.getRejectConfirmed(),
                entity.getConclusion(),
                entity.getFailureTypeL1Code(),
                entity.getFailureTypeL2Code(),
                entity.getFailureTypeL3Code());
    }
}
