package com.nexperia.qms.actions;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;

/**
 * A D5 permanent corrective action (requirement 3.6), always derived from a root
 * cause found in D4.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("corrective_action")
public class CorrectiveAction extends BaseEntity {

    @TableId(value = "corrective_action_id", type = IdType.INPUT)
    private String correctiveActionId;

    private String rootCauseId;

    /** Denormalised so the report and the ledger can group by complaint directly. */
    private String complaintId;

    private String nexSampleNumber;
    private String customerSampleId;

    /** What is going to be done; mandatory. */
    private String plannedActionDesc;

    private String ownerId;

    /** When it should be implemented; mandatory. */
    private LocalDate targetDate;

    /** One of {@link CorrectiveStatus}. */
    private String statusCode;
}
