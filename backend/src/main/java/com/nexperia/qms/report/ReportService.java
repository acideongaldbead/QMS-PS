package com.nexperia.qms.report;

import com.nexperia.qms.actions.mapper.PreventionFileUpdateMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.report.dto.ReportDtos;
import com.nexperia.qms.report.mail.ReportMailer;
import com.nexperia.qms.report.mapper.ApprovalTaskMapper;
import com.nexperia.qms.report.mapper.ReportDistributionMapper;
import com.nexperia.qms.report.mapper.ReportMapper;
import com.nexperia.qms.report.mapper.ReportTeamMemberMapper;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * D8 reporting and settlement (requirement 3.9): assemble the 8D report from the
 * D1-D7 content, export it as Word, send it to the customer as Sales Quality, and
 * close the complaint on the send.
 *
 * The three date rules live here and nowhere else: the send stamps start = close =
 * the send day, and the target defaults to start + 14 days.
 */
@Service
public class ReportService {

    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D8 = "D8";
    private static final String STATUS_DRAFTING = "COMPLAINT_S06";
    private static final String STATUS_CLOSED = "COMPLAINT_S07";

    private static final String TYPE_INTERIM = "INTERIM";
    private static final String TYPE_FINAL = "FINAL";

    /** report_8d.approval_status: DRAFT -> PENDING -> APPROVED / REJECTED. */
    private static final String APPROVAL_DRAFT = "DRAFT";
    private static final String APPROVAL_PENDING = "PENDING";
    private static final String APPROVAL_APPROVED = "APPROVED";
    private static final String APPROVAL_REJECTED = "REJECTED";

    /** approval_task.status_code, seeded by V4 as APPROVAL_*. */
    private static final String TASK_PENDING = "APPROVAL_PENDING";
    private static final String TASK_APPROVED = "APPROVAL_APPROVED";
    private static final String TASK_REJECTED = "APPROVAL_REJECTED";

    private static final String TEMPLATE_CODE = "XTE-0071";
    private static final String CLOSE_REASON_NORMAL = "CLOSE_NORMAL";
    private static final String CHANNEL_EMAIL = "邮件";
    private static final int TARGET_DAYS = 14;

    private final ReportMapper reportMapper;
    private final ReportTeamMemberMapper teamMemberMapper;
    private final ReportDistributionMapper distributionMapper;
    private final ApprovalTaskMapper approvalTaskMapper;
    private final ReportContentAssembler assembler;
    private final ReportDocxWriter docxWriter;
    private final ReportPdfWriter pdfWriter;
    private final ReportMailer reportMailer;
    private final ComplaintMapper complaintMapper;
    private final PreventionFileUpdateMapper preventionMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;

    public ReportService(ReportMapper reportMapper,
                         ReportTeamMemberMapper teamMemberMapper,
                         ReportDistributionMapper distributionMapper,
                         ApprovalTaskMapper approvalTaskMapper,
                         ReportContentAssembler assembler,
                         ReportDocxWriter docxWriter,
                         ReportPdfWriter pdfWriter,
                         ReportMailer reportMailer,
                         ComplaintMapper complaintMapper,
                         PreventionFileUpdateMapper preventionMapper,
                         DocumentNumberService documentNumberService,
                         AuditLogService auditLogService) {
        this.reportMapper = reportMapper;
        this.teamMemberMapper = teamMemberMapper;
        this.distributionMapper = distributionMapper;
        this.approvalTaskMapper = approvalTaskMapper;
        this.assembler = assembler;
        this.docxWriter = docxWriter;
        this.pdfWriter = pdfWriter;
        this.reportMailer = reportMailer;
        this.complaintMapper = complaintMapper;
        this.preventionMapper = preventionMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<ReportDtos.ReportView> list(String complaintId) {
        requireComplaint(complaintId);
        return reportMapper.findByComplaint(complaintId).stream().map(this::toView).toList();
    }

    @Transactional(readOnly = true)
    public ReportDtos.ReportContent view(String reportId) {
        return assembler.assemble(toView(requireReport(reportId)));
    }

    @Transactional
    public ReportDtos.ReportView generate(String complaintId, String reportType) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        String type = normalizeType(reportType);
        requireReadyForReport(complaintId);

        Report8D report = new Report8D();
        report.setReportId(documentNumberService.nextReportId());
        report.setComplaintId(complaintId);
        report.setReportType(type);
        report.setVersionNo("V1.0");
        report.setCurrentStep(STAGE_D8);
        report.setApprovalStatus(APPROVAL_DRAFT);
        report.setGeneratedAt(OffsetDateTime.now());
        report.setTemplateCode(TEMPLATE_CODE);
        reportMapper.insert(report);

        snapshotTeam(report.getReportId(), complaint);
        advanceComplaintToDrafting(complaint, "生成 8D 报告：" + report.getReportId());

        auditLogService.record(AuditActions.CREATE, "Report8D", complaintId,
                "生成 8D 报告：" + report.getReportId() + "（" + typeLabel(type) + "）");
        return toView(report);
    }

    @Transactional
    public byte[] exportDocx(String reportId) {
        Report8D report = requireReport(reportId);
        byte[] bytes = docxWriter.write(assembler.assemble(toView(report)));
        auditLogService.record(AuditActions.EXPORT, "Report8D", report.getComplaintId(),
                "导出 8D 报告 Word：" + reportId);
        return bytes;
    }

    /** The read-only copy, for circulating rather than editing. */
    @Transactional
    public byte[] exportPdf(String reportId) {
        Report8D report = requireReport(reportId);
        byte[] bytes = pdfWriter.write(assembler.assemble(toView(report)));
        auditLogService.record(AuditActions.EXPORT, "Report8D", report.getComplaintId(),
                "导出 8D 报告 PDF：" + reportId);
        return bytes;
    }

    /** Who may approve reports, for the submit dialog. */
    @Transactional(readOnly = true)
    public List<ReportDtos.Approver> approvers() {
        return approvalTaskMapper.findApprovers();
    }

    /**
     * Hands a draft - or a report that was sent back - to an approver.
     *
     * Resubmitting after a rejection is allowed on purpose: the report owner is
     * expected to fix what the comment named and try again.
     */
    @Transactional
    public ReportDtos.ReportView submit(String reportId, ReportDtos.SubmitRequest request) {
        Report8D report = requireReport(reportId);
        Complaint complaint = requireComplaint(report.getComplaintId());
        requireOpen(complaint);
        requireNotAlreadyInApproval(report);

        String approverId = request.approverId();
        boolean mayApprove = approvalTaskMapper.findApprovers().stream()
                .anyMatch(candidate -> candidate.employeeId().equals(approverId));
        if (!mayApprove) {
            throw new IllegalArgumentException("审批人不存在或不具备审批权限：" + approverId);
        }

        String approvalId = documentNumberService.nextApprovalId();
        String me = CurrentUserContext.employeeId();
        approvalTaskMapper.insert(approvalId, reportId, approverId, me);

        report.setApprovalStatus(APPROVAL_PENDING);
        reportMapper.updateById(report);

        auditLogService.record(AuditActions.CREATE, "ApprovalTask", report.getComplaintId(),
                "提交 8D 报告 " + reportId + " 审批（审批单 " + approvalId + "，审批人 " + approverId + "）");
        return toView(report);
    }

    /**
     * The approver's decision.
     *
     * Only the person named on the pending task may decide - that is what makes
     * the home page's "待我审批" card mean something. A rejection must carry a
     * comment, since the report owner works from it.
     */
    @Transactional
    public ReportDtos.ReportView approve(String reportId, ReportDtos.ApprovalRequest request) {
        Report8D report = requireReport(reportId);
        Complaint complaint = requireComplaint(report.getComplaintId());
        requireOpen(complaint);

        ApprovalTaskMapper.ApprovalRow task = approvalTaskMapper.findLatestByReport(reportId);
        if (task == null || !TASK_PENDING.equals(task.statusCode())) {
            throw new IllegalStateException("该报告当前没有待审批任务");
        }
        String me = CurrentUserContext.employeeId();
        if (!Objects.equals(task.approverId(), me)) {
            throw new AccessDeniedException("只有该报告的审批人（" + task.approverName() + "）可以给出结论");
        }

        boolean approved = Boolean.TRUE.equals(request.approved());
        String comment = request.comment() == null ? null : request.comment().trim();
        if (!approved && (comment == null || comment.isEmpty())) {
            throw new IllegalArgumentException("驳回时必须填写审批意见");
        }

        approvalTaskMapper.complete(task.approvalId(),
                approved ? TASK_APPROVED : TASK_REJECTED, comment, me);

        report.setApprovalStatus(approved ? APPROVAL_APPROVED : APPROVAL_REJECTED);
        reportMapper.updateById(report);

        auditLogService.recordValueChange(approved ? AuditActions.APPROVE : AuditActions.REJECT,
                "Report8D", report.getComplaintId(), TASK_PENDING,
                (approved ? TASK_APPROVED : TASK_REJECTED) + (comment == null ? "" : "：" + comment));
        return toView(report);
    }

    @Transactional
    public ReportDtos.SendResult send(String reportId, ReportDtos.SendRequest request) {
        Report8D report = requireReport(reportId);
        Complaint complaint = requireComplaint(report.getComplaintId());
        requireOpen(complaint);

        // Approval gates the send: the recipient is the customer, and sending
        // closes the complaint, so both are irreversible enough to need a second
        // pair of eyes first.
        if (!APPROVAL_APPROVED.equals(report.getApprovalStatus())) {
            throw new IllegalStateException("报告需先提交审批并获得批准才能发送，当前状态："
                    + approvalLabel(report.getApprovalStatus()));
        }

        List<String> to = splitAddresses(request.recipient());
        List<String> cc = splitAddresses(request.ccList());
        byte[] docx = docxWriter.write(assembler.assemble(toView(report)));

        // Send first: a failure here throws and rolls back, so no communication
        // log can claim a send that never left.
        reportMailer.send(new ReportMailer.ReportMail(
                to, cc, request.subject(), request.body(),
                "8D_Report_" + complaint.getComplaintId() + "_" + report.getVersionNo() + ".docx",
                docx));

        LocalDate today = LocalDate.now();

        ReportDistribution log = new ReportDistribution();
        log.setReportId(reportId);
        log.setSenderId(CurrentUserContext.employeeId());
        log.setRecipient(String.join(";", to));
        log.setCcList(cc.isEmpty() ? null : String.join(";", cc));
        log.setSentAt(OffsetDateTime.now());
        log.setAttachmentVersion(report.getVersionNo());
        log.setChannel(CHANNEL_EMAIL);
        log.setDistributionList(log.getRecipient() + (cc.isEmpty() ? "" : ";\nCC: " + log.getCcList()));
        distributionMapper.insert(log);

        // Requirement 3.9 date rules: start = close = the send day; target defaults
        // to start + 14 days and is only filled the first time.
        report.setReportStartDate(today);
        report.setReportCloseDate(today);
        if (report.getReportTargetDate() == null) {
            report.setReportTargetDate(today.plusDays(TARGET_DAYS));
        }
        reportMapper.updateById(report);

        closeComplaint(complaint, today, reportId);

        auditLogService.record(AuditActions.SEND, "Report8D", report.getComplaintId(),
                "发送 8D 报告 " + reportId + " 给客户：" + log.getRecipient()
                        + "（渠道 " + reportMailer.name() + "）");
        auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "Complaint",
                complaint.getComplaintId(), STATUS_DRAFTING, STATUS_CLOSED + "（报告发送结案）");

        ReportDtos.DistributionView distribution = distributionMapper.findByReport(reportId).stream()
                .findFirst()
                .map(d -> new ReportDtos.DistributionView(
                        d.logId(), d.senderName(), d.recipient(), d.ccList(),
                        d.sentAt(), d.attachmentVersion(), d.channel()))
                .orElse(null);
        return new ReportDtos.SendResult(toView(report), distribution);
    }

    // ------------------------------------------------------------------ helpers

    /** Snapshots the D1 cross-functional team so a later staff change cannot rewrite history. */
    private void snapshotTeam(String reportId, Complaint complaint) {
        record Role(String function, String employeeId, int order) {
        }
        List<Role> roles = List.of(
                new Role("Problem Owner", complaint.getComplaintOwnerId(), 1),
                new Role("Coordinator", complaint.getCoordinatorId(), 2),
                new Role("Verification Owner", complaint.getVerificationOwnerId(), 3),
                new Role("Report Owner", complaint.getReportOwnerId(), 4));

        Set<String> ids = new LinkedHashSet<>();
        roles.stream().map(Role::employeeId).filter(Objects::nonNull).forEach(ids::add);
        var byId = new java.util.HashMap<String, ReportMapper.EmployeeRow>();
        if (!ids.isEmpty()) {
            reportMapper.findEmployeeRows(ids).forEach(e -> byId.put(e.employeeId(), e));
        }
        for (Role role : roles) {
            if (role.employeeId() == null) {
                continue;
            }
            ReportMapper.EmployeeRow e = byId.get(role.employeeId());
            ReportTeamMember member = new ReportTeamMember();
            member.setReportId(reportId);
            member.setFunctionName(role.function());
            member.setEmployeeId(role.employeeId());
            member.setMemberName(e == null ? role.employeeId() : e.name());
            member.setJobTitle(e == null ? null : e.jobTitle());
            member.setSortOrder(role.order());
            teamMemberMapper.insert(member);
        }
    }

    /** The D6/D7 precondition the prototype's close card states: everything settled first. */
    private void requireReadyForReport(String complaintId) {
        List<String> problems = new ArrayList<>();
        int outstanding = preventionMapper.countOutstanding(complaintId);
        if (outstanding > 0) {
            problems.add(outstanding + " 个预防文件尚未更新完成");
        }
        int unverified = reportMapper.countUnverifiedActions(complaintId);
        if (unverified > 0) {
            problems.add(unverified + " 条纠正措施尚未验证通过");
        }
        if (!problems.isEmpty()) {
            throw new IllegalStateException("报告生成前置条件未满足：" + String.join("；", problems));
        }
    }

    private void closeComplaint(Complaint complaint, LocalDate sendDate, String reportId) {
        complaint.setCloseDate(sendDate);
        complaint.setCloseReasonCode(CLOSE_REASON_NORMAL);
        complaint.setStatusCode(STATUS_CLOSED);
        complaint.setCurrentStage(STAGE_D8);
        complaintMapper.updateById(complaint);
    }

    private void advanceComplaintToDrafting(Complaint complaint, String detail) {
        boolean stageForward = stageIndex(STAGE_D8) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(STATUS_DRAFTING) > statusOrder(complaint.getStatusCode());
        if (!stageForward && !statusForward) {
            return;
        }
        if (stageForward) {
            complaint.setCurrentStage(STAGE_D8);
        }
        if (statusForward) {
            complaint.setStatusCode(STATUS_DRAFTING);
        }
        complaintMapper.updateById(complaint);
        auditLogService.record(AuditActions.STATUS_CHANGE, "Complaint",
                complaint.getComplaintId(), detail);
    }

    /** Refuses a second submission while one is still open, or after approval. */
    private void requireNotAlreadyInApproval(Report8D report) {
        if (APPROVAL_PENDING.equals(report.getApprovalStatus())) {
            throw new IllegalStateException("报告已在审批中，不能重复提交");
        }
        if (APPROVAL_APPROVED.equals(report.getApprovalStatus())) {
            throw new IllegalStateException("报告已批准，不能重新提交审批");
        }
    }

    private ReportDtos.ReportView toView(Report8D r) {
        return new ReportDtos.ReportView(
                r.getReportId(), r.getComplaintId(), r.getReportType(), typeLabel(r.getReportType()),
                r.getVersionNo(), r.getCurrentStep(),
                r.getApprovalStatus(), approvalLabel(r.getApprovalStatus()),
                r.getReportStartDate(), r.getReportTargetDate(), r.getReportCloseDate(),
                r.getGeneratedAt(), r.getTemplateCode(),
                toApprovalView(approvalTaskMapper.findLatestByReport(r.getReportId())));
    }

    private ReportDtos.ApprovalView toApprovalView(ApprovalTaskMapper.ApprovalRow row) {
        if (row == null) {
            return null;
        }
        return new ReportDtos.ApprovalView(
                row.approvalId(), row.approverId(), row.approverName(),
                row.statusCode(), approvalTaskLabel(row.statusCode()), row.comment(),
                row.pushedAt(), row.completedAt());
    }

    private String approvalTaskLabel(String status) {
        return switch (status == null ? "" : status) {
            case "APPROVAL_PENDING" -> "待审批";
            case "APPROVAL_APPROVED" -> "已批准";
            case "APPROVAL_REJECTED" -> "已驳回";
            case "APPROVAL_WITHDRAWN" -> "已撤回";
            default -> status;
        };
    }

    private Complaint requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
        return complaint;
    }

    private Report8D requireReport(String reportId) {
        Report8D report = reportMapper.selectById(reportId);
        if (report == null) {
            throw new NotFoundException("8D 报告不存在：" + reportId);
        }
        return report;
    }

    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续处理报告");
        }
    }

    private String normalizeType(String reportType) {
        if (reportType == null || reportType.isBlank()) {
            return TYPE_INTERIM;
        }
        String upper = reportType.trim().toUpperCase();
        if (!TYPE_INTERIM.equals(upper) && !TYPE_FINAL.equals(upper)) {
            throw new IllegalArgumentException("报告类型只能是 INTERIM 或 FINAL：" + reportType);
        }
        return upper;
    }

    private String typeLabel(String type) {
        if (TYPE_FINAL.equals(type)) {
            return "终期报告";
        }
        return TYPE_INTERIM.equals(type) ? "中期报告" : type;
    }

    private String approvalLabel(String status) {
        return switch (status == null ? "" : status) {
            case "DRAFT" -> "草稿";
            case "PENDING" -> "审批中";
            case "APPROVED" -> "已批准";
            case "REJECTED" -> "已驳回";
            default -> status;
        };
    }

    private static List<String> splitAddresses(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        return Set.of(raw.split("[;,\\s]+")).stream().filter(s -> !s.isBlank()).toList();
    }

    private int stageIndex(String stage) {
        int index = STAGE_ORDER.indexOf(stage);
        return index < 0 ? -1 : index;
    }

    private int statusOrder(String status) {
        if (status == null) {
            return 0;
        }
        return switch (status) {
            case "COMPLAINT_S01" -> 1;
            case "COMPLAINT_S02" -> 2;
            case "COMPLAINT_S03" -> 3;
            case "COMPLAINT_S04" -> 4;
            case "COMPLAINT_S05" -> 5;
            case "COMPLAINT_S06" -> 6;
            case "COMPLAINT_S07" -> 7;
            default -> 0;
        };
    }
}
