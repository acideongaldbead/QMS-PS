package com.nexperia.qms.report;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * A D8 8D report (requirement 3.9), assembled from the D1-D7 content.
 *
 * The three dates carry the requirement's rules, which live in the baseline
 * column comments: {@code reportStartDate} = the day the report was sent to the
 * customer (filled automatically, never edited); {@code reportTargetDate} defaults
 * to start + 14 days and may be adjusted; {@code reportCloseDate} equals the send
 * day. They stay null until the report is sent.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("report_8d")
public class Report8D extends BaseEntity {

    @TableId(value = "report_id", type = IdType.INPUT)
    private String reportId;

    private String complaintId;

    /** INTERIM (中期) or FINAL (终期); the label is applied by the UI. */
    private String reportType;

    private String versionNo;

    /** D1-D8; where the report is in its editing progress. */
    private String currentStep;

    private LocalDate reportStartDate;
    private LocalDate reportTargetDate;
    private LocalDate reportCloseDate;

    /** DRAFT / PENDING / APPROVED / REJECTED (approval flow lands in a later task). */
    private String approvalStatus;

    private OffsetDateTime generatedAt;

    /** Which layout the export follows; XTE-0071 for phase 1 (Q-10). */
    private String templateCode;
}
