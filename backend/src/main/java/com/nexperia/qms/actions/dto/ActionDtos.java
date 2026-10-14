package com.nexperia.qms.actions.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class ActionDtos {

    private ActionDtos() {
    }

    // ------------------------------------------------------------- D5

    /**
     * A corrective action is always derived from a root cause, so the root cause is
     * mandatory; the service checks that it belongs to the same complaint.
     */
    public record CorrectiveActionRequest(
            @NotBlank(message = "根因不能为空") String rootCauseId,
            @Size(max = 64) String nexSampleNumber,
            @Size(max = 64) String customerSampleId,
            @NotBlank(message = "计划措施不能为空") String plannedActionDesc,
            @NotBlank(message = "责任人不能为空") String ownerId,
            @NotNull(message = "目标日期不能为空") LocalDate targetDate,
            String statusCode) {
    }

    public record CorrectiveActionView(
            String correctiveActionId,
            String rootCauseId,
            String rootCauseSummary,
            String complaintId,
            String nexSampleNumber,
            String customerSampleId,
            String plannedActionDesc,
            String ownerId,
            String ownerName,
            LocalDate targetDate,
            String statusCode,
            String statusName,
            /** The newest D6 check, or null when none has been recorded. */
            Long latestVerificationId,
            LocalDate actualCompletionDate,
            Boolean isEffective,
            String verificationResult,
            OffsetDateTime verifiedAt,
            String verifiedByName,
            int verificationCount) {
    }

    // ------------------------------------------------------------- D6

    /**
     * Implementation feedback and effectiveness check.
     *
     * {@code isEffective} may be left null to record progress without judging yet;
     * once it is set, the action's status follows it automatically.
     */
    public record VerificationRequest(
            LocalDate actualCompletionDate,
            String verificationResult,
            Boolean isEffective) {
    }

    public record VerificationView(
            Long verificationId,
            String correctiveActionId,
            LocalDate actualCompletionDate,
            String verificationResult,
            Boolean isEffective,
            String verifiedBy,
            String verifiedByName,
            OffsetDateTime verifiedAt) {
    }

    public record CorrectiveActionDetail(
            CorrectiveActionView action,
            List<VerificationView> verifications) {
    }

    // ------------------------------------------------------------- D7

    public record PreventionRequest(
            @NotBlank(message = "文件类型不能为空") String fileTypeCode,
            @Size(max = 64) String nexSampleNumber,
            @Size(max = 64) String customerSampleId,
            @Size(max = 128) String controlProgram,
            @Size(max = 64) String referenceNumber,
            String statusCode) {
    }

    public record PreventionView(
            Long updateId,
            String complaintId,
            String nexSampleNumber,
            String customerSampleId,
            String fileTypeCode,
            String fileTypeName,
            String controlProgram,
            String referenceNumber,
            String statusCode,
            String statusName,
            String createdBy,
            String createdByName,
            OffsetDateTime createdAt) {
    }
}
