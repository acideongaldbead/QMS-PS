package com.nexperia.qms.complaint.dto;

/**
 * Display names resolved from the complaint's 1:1 blocks out to their master data,
 * so the detail page does not have to make a lookup per field.
 *
 * Every component maps to a column in ComplaintMapper.findLabels.
 */
public record ComplaintLabels(
        String customerName,
        String contactName,
        String contactEmail,
        String shipToName,
        String productDescription,
        String ownerName,
        String coordinatorName,
        String verificationOwnerName,
        String reportOwnerName,
        /** Name of the person who registered the complaint (complaint.created_by). */
        String createdByName,
        String complaintTypeName,
        String priorityName,
        String failureLocationName,
        String subSegmentName,
        String customerFailureModeName,
        String statusName) {
}
