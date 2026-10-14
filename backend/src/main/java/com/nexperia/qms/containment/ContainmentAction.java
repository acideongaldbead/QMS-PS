package com.nexperia.qms.containment;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;

/** A D3 containment action (requirement 3.4). */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("containment_action")
public class ContainmentAction extends BaseEntity {

    @TableId(value = "action_id", type = IdType.INPUT)
    private String actionId;

    private String complaintId;

    private String nexSampleNumber;
    private String customerSampleNumber;

    /** The action to be taken; mandatory. */
    private String plannedAction;

    private String ownerId;

    /**
     * When the action is planned to finish. Added by migration V16 at the
     * business's request; its presence is what makes the schema's "completion
     * earlier than planned" check possible.
     */
    private LocalDate plannedCompletionDate;

    /**
     * Stamped when the action reaches a terminal status, and editable afterwards
     * to correct it.
     */
    private LocalDate completedDate;

    /** One of {@link ContainmentStatus}. */
    private String statusCode;

    /** What actually happened. */
    private String result;
}
