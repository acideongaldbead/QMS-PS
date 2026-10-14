package com.nexperia.qms.common.exception;

import org.springframework.dao.DataIntegrityViolationException;

import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns a constraint violation into a sentence a quality engineer can act on.
 *
 * The service layer already checks the references it can explain; whatever still
 * reaches the database is caught here so the user never sees a raw constraint
 * name, while the name is still logged for whoever has to debug it.
 */
final class DataIntegrityTranslator {

    private static final Pattern CONSTRAINT = Pattern.compile("constraint \"([^\"]+)\"");
    private static final Pattern DUPLICATE_KEY = Pattern.compile("duplicate key value");

    private static final Map<String, String> FOREIGN_KEY_MESSAGES = Map.ofEntries(
            Map.entry("fk_complaint_complaint_type_code", "投诉类型不存在或已停用"),
            Map.entry("fk_complaint_priority_code", "优先级不存在或已停用"),
            Map.entry("fk_complaint_failure_location_code", "失效位置不存在或已停用"),
            Map.entry("fk_complaint_status_code", "投诉状态码不存在或已停用"),
            Map.entry("fk_complaint_complaint_owner_id", "投诉负责人不存在或已停用"),
            Map.entry("fk_complaint_coordinator_id", "协调人不存在或已停用"),
            Map.entry("fk_complaint_verification_owner_id", "验证负责人不存在或已停用"),
            Map.entry("fk_complaint_report_owner_id", "报告负责人不存在或已停用"),
            Map.entry("fk_quality_partner_quality_partner_code", "质量合作伙伴不存在或已停用"),
            Map.entry("fk_quality_partner_contact_person_id", "联系人不属于所选质量合作伙伴"),
            Map.entry("fk_quality_partner_sub_segment_code", "子分部不存在或已停用"),
            Map.entry("fk_quality_partner_ship_to_sold_to_code", "收货/售达方不属于所选质量合作伙伴"),
            Map.entry("fk_product_info_material_code", "产品物料编码不存在或已停用"),
            Map.entry("fk_product_info_product_type_code", "产品类型不存在或已停用"),
            Map.entry("fk_product_info_packing_type_code", "包装类型不存在或已停用"),
            Map.entry("fk_failure_description_customer_failure_mode_code", "客户失效模式不存在或已停用"),
            Map.entry("fk_sample_failure_type_l1_code", "一级失效类型不存在或已停用"),
            Map.entry("fk_sample_failure_type_l2_code", "二级失效类型不存在或已停用"),
            Map.entry("fk_sample_failure_type_l3_code", "三级失效类型不存在或已停用"));

    private DataIntegrityTranslator() {
    }

    /** A user-facing sentence, plus the raw detail for logging. */
    record Translation(String message, String constraintName) {
    }

    static Translation translate(DataIntegrityViolationException ex) {
        Throwable cause = ex.getMostSpecificCause();
        String text = cause == null || cause.getMessage() == null ? "" : cause.getMessage();

        if (DUPLICATE_KEY.matcher(text).find()) {
            return new Translation("该记录已存在，不能重复创建", null);
        }

        Matcher matcher = CONSTRAINT.matcher(text);
        if (matcher.find()) {
            String name = matcher.group(1);
            String friendly = FOREIGN_KEY_MESSAGES.get(name);
            if (friendly != null) {
                return new Translation(friendly, name);
            }
            return new Translation("引用的数据不存在或已被停用", name);
        }

        return new Translation("数据校验未通过，请检查输入内容", null);
    }
}
