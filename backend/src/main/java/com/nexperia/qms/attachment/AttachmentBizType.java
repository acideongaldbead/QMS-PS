package com.nexperia.qms.attachment;

import java.util.Map;
import java.util.Set;

/**
 * The biz_type values an attachment may carry.
 *
 * The schema links attachments polymorphically (biz_type + biz_id, no foreign
 * key), so the database cannot tell a typo from a real reference. This list plus
 * the existence check in {@code AttachmentMapper.countParent} is what keeps an
 * attachment from pointing at nothing.
 */
public final class AttachmentBizType {

    public static final String COMPLAINT = "Complaint";
    public static final String SAMPLE = "Sample";
    public static final String SHIPMENT = "Shipment";
    public static final String VERIFICATION_TASK = "VerificationTask";
    public static final String CONTAINMENT_ACTION = "ContainmentAction";
    public static final String ROOT_CAUSE = "RootCause";
    public static final String CORRECTIVE_ACTION = "CorrectiveAction";
    public static final String PREVENTION_FILE = "PreventionFileUpdate";
    public static final String REPORT_8D = "Report8D";
    public static final String KNOWLEDGE_ARTICLE = "KnowledgeArticle";

    /** biz_type -> Chinese label, for messages and the attachment centre. */
    public static final Map<String, String> LABELS = Map.ofEntries(
            Map.entry(COMPLAINT, "投诉单"),
            Map.entry(SAMPLE, "客诉样品"),
            Map.entry(SHIPMENT, "物流批次"),
            Map.entry(VERIFICATION_TASK, "验证任务"),
            Map.entry(CONTAINMENT_ACTION, "遏制措施"),
            Map.entry(ROOT_CAUSE, "根因分析"),
            Map.entry(CORRECTIVE_ACTION, "纠正措施"),
            Map.entry(PREVENTION_FILE, "预防文件更新"),
            Map.entry(REPORT_8D, "8D报告"),
            Map.entry(KNOWLEDGE_ARTICLE, "知识文档"));

    public static final Set<String> ALL = LABELS.keySet();

    /**
     * Which permission allows writing to each business type.
     *
     * {@code AttachmentController.MAY_ATTACH} is only a coarse "may attach
     * something" gate -- it is a flat hasAnyAuthority over every edit code, so on
     * its own any role holding a single edit permission could attach a file to any
     * record. This map narrows that to the record type actually being written:
     * without it an engineer holding {@code rootcause:edit} could attach a file to
     * a knowledge document they are not allowed to maintain.
     *
     * Shipment keeps the same either/or its own controller uses.
     */
    public static final Map<String, Set<String>> WRITE_PERMISSIONS = Map.ofEntries(
            Map.entry(COMPLAINT, Set.of("complaint:edit")),
            Map.entry(SAMPLE, Set.of("sample:edit")),
            Map.entry(SHIPMENT, Set.of("sample:edit", "complaint:edit")),
            Map.entry(VERIFICATION_TASK, Set.of("verify:edit")),
            Map.entry(CONTAINMENT_ACTION, Set.of("containment:edit")),
            Map.entry(ROOT_CAUSE, Set.of("rootcause:edit")),
            Map.entry(CORRECTIVE_ACTION, Set.of("action:edit")),
            Map.entry(PREVENTION_FILE, Set.of("prevention:edit")),
            Map.entry(REPORT_8D, Set.of("report:edit")),
            Map.entry(KNOWLEDGE_ARTICLE, Set.of("knowledge:manage")));

    private AttachmentBizType() {
    }

    public static String label(String bizType) {
        return LABELS.getOrDefault(bizType, bizType);
    }

    public static boolean isKnown(String bizType) {
        return ALL.contains(bizType);
    }

    /** The permissions that allow writing to {@code bizType}; empty for unknown types. */
    public static Set<String> writePermissions(String bizType) {
        return WRITE_PERMISSIONS.getOrDefault(bizType, Set.of());
    }
}
