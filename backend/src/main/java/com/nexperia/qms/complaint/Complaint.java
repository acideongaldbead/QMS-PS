package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;

/**
 * The 8D flow's carrying document (requirement 3.1.2).
 *
 * {@code createdBy} is inherited from BaseEntity but is ALSO a business field --
 * the schema comment calls it 发起人 "自动填入当前登录用户，不可修改". That is why
 * no separate initiator column exists.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("complaint")
public class Complaint extends BaseEntity {

    @TableId(value = "complaint_id", type = IdType.INPUT)
    private String complaintId;

    /** status_code: the process node plus sub-state, e.g. COMPLAINT_S01 登记-已启动. */
    private String statusCode;

    /** 8D stage D0-D8. Not derivable from status_code: D2 covers two statuses. */
    private String currentStage;

    private String complaintTypeCode;
    private String priorityCode;
    private String failureLocationCode;

    /** 8D / 4C. 4C is reserved for phase 2. */
    private String processType;

    private String complaintOwnerId;
    private String coordinatorId;
    private String verificationOwnerId;
    private String reportOwnerId;

    private LocalDate startDate;
    private LocalDate targetDate;
    private LocalDate customerTargetDate;
    private LocalDate closeDate;

    private Boolean isValid;
    private String closeReasonCode;
    private String customerReferenceId;

    /**
     * The D3 decision (PS-039): null until judged, true to run containment, false
     * to skip straight to D4. Added by migration V15 because the baseline had
     * nowhere to record it and the stage alone cannot distinguish "skipped" from
     * "not started".
     */
    private Boolean containmentRequired;

    private String containmentDecisionNote;
}
