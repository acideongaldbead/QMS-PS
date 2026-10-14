package com.nexperia.qms.actions;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * The D6 implementation feedback and effectiveness check for one corrective action
 * (requirement 3.7).
 *
 * The table has no status column of its own: {@code isEffective} is the outcome,
 * and the action's status is derived from it, which is what "the result updates
 * the status automatically" means.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("action_verification")
public class ActionVerification extends BaseEntity {

    @TableId(value = "verification_id", type = IdType.AUTO)
    private Long verificationId;

    private String correctiveActionId;

    /** Filled in by the owner when the action is actually finished. */
    private LocalDate actualCompletionDate;

    private String verificationResult;

    /** null while the check has not been made. */
    private Boolean isEffective;

    private String verifiedBy;
    private OffsetDateTime verifiedAt;
}
