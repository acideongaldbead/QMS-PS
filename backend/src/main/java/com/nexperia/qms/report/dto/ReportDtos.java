package com.nexperia.qms.report.dto;

import com.nexperia.qms.actions.dto.ActionDtos;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import com.nexperia.qms.containment.dto.ContainmentDtos;
import com.nexperia.qms.rootcause.dto.RootCauseDtos;
import com.nexperia.qms.verification.dto.VerificationDtos;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class ReportDtos {

    private ReportDtos() {
    }

    /** The report header (report_8d). */
    public record ReportView(
            String reportId, String complaintId,
            String reportType, String reportTypeName,
            String versionNo, String currentStep,
            String approvalStatus, String approvalStatusName,
            LocalDate reportStartDate, LocalDate reportTargetDate, LocalDate reportCloseDate,
            OffsetDateTime generatedAt, String templateCode,
            /** The newest approval task, or null when the report has never been submitted. */
            ApprovalView approval) {
    }

    /**
     * The approval step of a report, read from the shared approval_task table.
     * The approver is who owes (or gave) the decision, so the screen can show the
     * approve buttons only to that person.
     */
    public record ApprovalView(
            String approvalId,
            String approverId,
            String approverName,
            String statusCode,
            String statusName,
            String comment,
            OffsetDateTime pushedAt,
            OffsetDateTime completedAt) {
    }

    /** An employee who may approve reports, for the submit dialog. */
    public record Approver(String employeeId, String name) {
    }

    /** Hands a generated report to an approver. */
    public record SubmitRequest(@NotBlank(message = "审批人不能为空") String approverId) {
    }

    /**
     * The approver's decision. A rejection must say why - it is what the report
     * owner works from - so the comment is required on that branch.
     */
    public record ApprovalRequest(
            @NotNull(message = "请给出审批结论") Boolean approved,
            String comment) {
    }

    public record GenerateRequest(@NotBlank(message = "报告类型不能为空") String reportType) {
    }

    public record SendRequest(
            @NotBlank(message = "收件人不能为空") String recipient,
            String ccList,
            @NotBlank(message = "邮件主题不能为空") String subject,
            @NotBlank(message = "邮件正文不能为空") String body) {
    }

    /** A row of the report's D1 cross-functional team table. */
    public record TeamMemberView(String functionName, String memberName, String jobTitle, String employeeId) {
    }

    /** A communication-log entry (report_distribution). */
    public record DistributionView(
            Long logId, String senderName, String recipient, String ccList,
            OffsetDateTime sentAt, String attachmentVersion, String channel) {
    }

    /**
     * The assembled report. The per-stage blocks are the very records the detail
     * screens already return, so the frontend reuses its existing types and the
     * report always reflects the latest D1-D7 content.
     */
    public record ReportContent(
            ReportView report,
            ComplaintResponses.Detail complaint,
            List<TeamMemberView> team,
            ContainmentDtos.ContainmentSummary containment,
            List<VerificationDtos.TaskView> verificationTasks,
            List<RootCauseDtos.RootCauseView> rootCauses,
            List<ActionDtos.CorrectiveActionView> correctiveActions,
            List<ActionDtos.PreventionView> preventionFiles,
            List<DistributionView> distributions) {
    }

    public record SendResult(ReportView report, DistributionView distribution) {
    }
}
