package com.nexperia.qms.verification.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class VerificationDtos {

    private VerificationDtos() {
    }

    /**
     * Create or reschedule a D2 task. The target completion date is mandatory
     * because the schema declares it NOT NULL and the business uses it to drive
     * the reminders.
     */
    public record TaskRequest(
            String sampleId,
            @NotBlank(message = "任务负责人不能为空") String taskOwnerId,
            LocalDate plannedStartDate,
            @NotNull(message = "目标完成日期不能为空") LocalDate targetCompletionDate,
            String taskStatus,
            String creationMode) {
    }

    public record TaskView(
            String taskId,
            String complaintId,
            String sampleId,
            String sampleCustomerSampleId,
            String taskOwnerId,
            String taskOwnerName,
            LocalDate plannedStartDate,
            LocalDate targetCompletionDate,
            String creationMode,
            String taskStatus,
            String taskStatusName,
            OffsetDateTime completedAt,
            int resultCount,
            /**
             * Set when the task is due after the complaint itself is due, which is
             * what requirement 3.3 means by flagging the conflict. A warning only.
             */
            String targetWarning) {
    }

    /** One test line. The failure type chain is validated as a L1 > L2 > L3 chain. */
    public record ResultRequest(
            @NotBlank(message = "测试项不能为空") @Size(max = 64) String testItem,
            String failureTypeL1Code,
            String failureTypeL2Code,
            String failureTypeL3Code,
            String resultConclusion) {
    }

    public record ResultView(
            Long resultId,
            String taskId,
            String testItem,
            String failureTypeL1Code,
            String failureTypeL1Name,
            String failureTypeL2Code,
            String failureTypeL2Name,
            String failureTypeL3Code,
            String failureTypeL3Name,
            String resultConclusion,
            String entryMode,
            String recordedBy,
            String recordedByName,
            OffsetDateTime recordedAt) {
    }

    public record TaskDetail(TaskView task, List<ResultView> results) {
    }

    /**
     * The D2 conclusion. {@code valid=false} closes the complaint directly, which
     * is the branch requirement 2.1 describes; a reason code is then required.
     */
    public record ValidityRequest(
            @NotNull(message = "请给出投诉是否有效的结论") Boolean valid,
            @Size(max = 32) String reasonCode,
            String conclusion) {
    }

    /** What the complaint became after the conclusion. */
    public record ValidityResult(
            String complaintId,
            boolean valid,
            String statusCode,
            String currentStage,
            LocalDate closeDate,
            String closeReasonCode) {
    }
}
