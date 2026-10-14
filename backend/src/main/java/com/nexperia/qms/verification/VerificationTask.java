package com.nexperia.qms.verification;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/** A D2 failure-analysis and verification task (requirement 3.3). */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("verification_task")
public class VerificationTask extends BaseEntity {

    @TableId(value = "task_id", type = IdType.INPUT)
    private String taskId;

    private String complaintId;

    /** Optional: a task can analyse one specific sample, or the complaint as a whole. */
    private String sampleId;

    private String taskOwnerId;

    private LocalDate plannedStartDate;

    private LocalDate targetCompletionDate;

    /** AUTO or MANUAL. */
    private String creationMode;

    /** One of {@link VerificationTaskStatus}. */
    private String taskStatus;

    private OffsetDateTime completedAt;
}
