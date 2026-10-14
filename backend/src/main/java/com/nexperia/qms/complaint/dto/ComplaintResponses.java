package com.nexperia.qms.complaint.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class ComplaintResponses {

    private ComplaintResponses() {
    }

    /**
     * The priority -> target-days rule, exposed so the wizard can preview the
     * target date as the user picks a priority. Serving it means the rule lives in
     * exactly one place instead of being duplicated in the frontend.
     */
    public record PriorityRule(String code, int days) {
    }

    /** What the client gets back after registering, including the computed dates. */
    public record Created(
            String complaintId,
            String statusCode,
            String currentStage,
            LocalDate startDate,
            LocalDate targetDate,
            LocalDate customerTargetDate,
            List<String> sampleIds) {
    }

    /** A stored sample together with the identifier the server assigned it. */
    public record SampleDetail(String sampleId, ComplaintRequests.Sample value) {
    }

    /**
     * One complaint ledger row (requirement 3.1.1's list columns).
     *
     * <p>This is the mapper's projection as well as the API shape: the aliases in
     * {@code ComplaintMapper.findLedger} are these component names, so the two can
     * only drift by editing one of them. Display names (status, priority, customer,
     * product, owner) are joined in by the query rather than resolved per row.
     *
     * <p>The 8D stage progress ("n/9") is deliberately not computed here: it is a
     * rendering detail, and the client already has the stage order and the close
     * reason.
     */
    public record LedgerRow(
            String complaintId,
            String statusCode,
            String statusName,
            String currentStage,
            String priorityCode,
            String priorityName,
            String customerName,
            String productCode,
            /** The product type dictionary name, which is what the ledger column shows. */
            String productTypeName,
            LocalDate startDate,
            LocalDate targetDate,
            LocalDate closeDate,
            String closeReasonCode,
            Integer processingDays,
            String ownerId,
            String ownerName,
            String customerReferenceId,
            /** Days past the target date; 0 when on time or already closed. */
            int overdueDays,
            /** complaint_related(complaint, current user): the "我相关" badge. */
            boolean mine) {
    }

    /**
     * A page of ledger rows plus the two tab counters. mineTotal/allTotal are the
     * unfiltered totals the tabs show (the prototype counts them the same way), so
     * switching tabs while a filter is applied does not change the badges.
     */
    public record LedgerPage(
            List<LedgerRow> items,
            long total,
            int page,
            int size,
            long mineTotal,
            long allTotal) {
    }

    /** What the client gets when a sample is added on its own. */
    public record CreatedSample(String sampleId) {
    }

    /**
     * Everything the detail page renders. The four 1:1 blocks are returned in the
     * same shape the wizard submits, so the form can be repopulated directly.
     */
    public record Detail(
            String complaintId,
            String statusCode,
            String currentStage,
            String processType,
            LocalDate startDate,
            LocalDate targetDate,
            LocalDate customerTargetDate,
            LocalDate closeDate,
            Boolean isValid,
            String closeReasonCode,
            String customerReferenceId,
            String createdBy,
            OffsetDateTime createdAt,
            /** Days past the target date; 0 when on time or already closed. */
            long overdueDays,
            ComplaintRequests.Header header,
            ComplaintRequests.QualityPartner qualityPartner,
            ComplaintRequests.Product product,
            ComplaintRequests.FailureDescription failureDescription,
            List<SampleDetail> samples,
            ComplaintLabels labels) {
    }
}
