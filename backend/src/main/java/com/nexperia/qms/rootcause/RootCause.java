package com.nexperia.qms.rootcause;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.OffsetDateTime;

/** A D4 root-cause entry (requirement 3.5). A complaint can have several. */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("root_cause")
public class RootCause extends BaseEntity {

    @TableId(value = "root_cause_id", type = IdType.INPUT)
    private String rootCauseId;

    private String complaintId;

    /** Rich text with images. */
    private String rootCauseDesc;

    /** Short text for reports and knowledge search. */
    private String rootCauseSummary;

    private String riskAssessment;

    /** INTERNAL or EXTERNAL: the flowchart's "is the root cause inside Nexperia?" branch. */
    private String responsibleOrgType;

    private String responsibleOrgCode;

    private String transferredToId;
    private OffsetDateTime transferredAt;

    /** One of {@link RootCauseStatus}. */
    private String statusCode;
}
