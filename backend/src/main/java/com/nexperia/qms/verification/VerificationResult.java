package com.nexperia.qms.verification;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.OffsetDateTime;

/**
 * One test line of a D2 task (requirement 3.3). Results may be entered one at a
 * time or as a batch summary; {@code entryMode} records which, because the two
 * are different working practices the business asked to distinguish.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("verification_result")
public class VerificationResult extends BaseEntity {

    @TableId(value = "result_id", type = IdType.AUTO)
    private Long resultId;

    private String taskId;

    /** e.g. X-Ray, electrical test. */
    private String testItem;

    private String failureTypeL1Code;
    private String failureTypeL2Code;
    private String failureTypeL3Code;

    private String resultConclusion;

    /** SINGLE or BATCH. */
    private String entryMode;

    private String recordedBy;
    private OffsetDateTime recordedAt;
}
