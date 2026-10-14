package com.nexperia.qms.complaintlog;

import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.complaintlog.dto.ComplaintLogDtos;
import com.nexperia.qms.complaintlog.mapper.ComplaintLogMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * The complaint's "沟通与流程日志" tab: the process trail from the audit log plus
 * the mails the 8D report was sent with, merged into one timeline, newest first.
 *
 * The labels live here rather than in the database: the audit rows store action
 * and business codes (CREATE, VerificationTask), and this is where they become
 * something a reader recognises.
 */
@Service
public class ComplaintLogService {

    private static final String KIND_AUDIT = "AUDIT";
    private static final String KIND_COMMUNICATION = "COMMUNICATION";

    private static final Map<String, String> ACTION_LABELS = Map.ofEntries(
            Map.entry("CREATE", "新增"),
            Map.entry("UPDATE", "修改"),
            Map.entry("DELETE", "删除"),
            Map.entry("STATUS_CHANGE", "状态变更"),
            Map.entry("EXPORT", "导出"),
            Map.entry("SEND", "发送给客户"),
            Map.entry("APPROVE", "审批通过"),
            Map.entry("REJECT", "审批驳回"),
            Map.entry("UPLOAD_REJECTED", "上传被拒"),
            Map.entry("LOGIN", "登录"),
            Map.entry("LOGIN_FAILED", "登录失败"));

    private static final Map<String, String> BIZ_LABELS = Map.ofEntries(
            Map.entry("Complaint", "投诉单"),
            Map.entry("Sample", "样品"),
            Map.entry("Shipment", "物流批次"),
            Map.entry("VerificationTask", "验证任务"),
            Map.entry("VerificationResult", "验证结果"),
            Map.entry("ContainmentAction", "遏制措施"),
            Map.entry("RootCause", "根因分析"),
            Map.entry("CorrectiveAction", "纠正措施"),
            Map.entry("ActionVerification", "措施验证"),
            Map.entry("PreventionFileUpdate", "预防文件"),
            Map.entry("Report8D", "8D 报告"),
            Map.entry("ApprovalTask", "报告审批"),
            Map.entry("Attachment", "附件"),
            Map.entry("ReportDistribution", "沟通日志"));

    private final ComplaintLogMapper complaintLogMapper;

    public ComplaintLogService(ComplaintLogMapper complaintLogMapper) {
        this.complaintLogMapper = complaintLogMapper;
    }

    @Transactional(readOnly = true)
    public List<ComplaintLogDtos.LogEntry> entries(String complaintId) {
        if (complaintLogMapper.countComplaint(complaintId) == 0) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }

        List<ComplaintLogDtos.LogEntry> entries = new ArrayList<>();
        for (ComplaintLogMapper.AuditRow row : complaintLogMapper.findAuditRows(complaintId)) {
            entries.add(new ComplaintLogDtos.LogEntry(
                    row.at(),
                    KIND_AUDIT,
                    row.actorName(),
                    label(row.bizType(), row.actionType()),
                    auditDetail(row),
                    tone(row.actionType())));
        }
        for (ComplaintLogMapper.CommunicationRow row : complaintLogMapper.findCommunications(complaintId)) {
            entries.add(new ComplaintLogDtos.LogEntry(
                    row.at(),
                    KIND_COMMUNICATION,
                    row.actorName(),
                    "8D 报告 · 发送给客户",
                    communicationDetail(row),
                    "done"));
        }

        entries.sort(Comparator.comparing(ComplaintLogDtos.LogEntry::at,
                Comparator.nullsLast(Comparator.reverseOrder())));
        return entries;
    }

    private static String label(String bizType, String actionType) {
        String biz = BIZ_LABELS.getOrDefault(bizType, bizType);
        String action = ACTION_LABELS.getOrDefault(actionType, actionType);
        return biz + " · " + action;
    }

    /** A status change reads as "before -> after"; anything else is the note. */
    private static String auditDetail(ComplaintLogMapper.AuditRow row) {
        String before = row.beforeValue();
        String after = row.afterValue();
        if (before != null && !before.isBlank() && after != null && !after.isBlank()) {
            return before + " → " + after;
        }
        return after != null ? after : before;
    }

    private static String communicationDetail(ComplaintLogMapper.CommunicationRow row) {
        StringBuilder text = new StringBuilder();
        text.append("收件人 ").append(row.recipient() == null ? "—" : row.recipient());
        if (row.ccList() != null && !row.ccList().isBlank()) {
            text.append("，抄送 ").append(row.ccList());
        }
        if (row.channel() != null && !row.channel().isBlank()) {
            text.append("，渠道 ").append(row.channel());
        }
        if (row.attachmentVersion() != null && !row.attachmentVersion().isBlank()) {
            text.append("，附件版本 ").append(row.attachmentVersion());
        }
        return text.toString();
    }

    /** Only failures and completed sends are worth colouring. */
    private static String tone(String actionType) {
        if ("REJECT".equals(actionType) || "UPLOAD_REJECTED".equals(actionType)
                || "LOGIN_FAILED".equals(actionType)) {
            return "warn";
        }
        if ("SEND".equals(actionType) || "APPROVE".equals(actionType)) {
            return "done";
        }
        return "";
    }
}
