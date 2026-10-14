package com.nexperia.qms.common.audit;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDate;

/**
 * One audited action (requirement 3.16, retained at least three years).
 *
 * {@code createdAt} is inherited and doubles as the action time; the schema names
 * it 操作时间 rather than keeping a separate timestamp.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("audit_log")
public class AuditLog extends BaseEntity {

    @TableId(value = "log_id", type = IdType.AUTO)
    private Long logId;

    private String operatorId;

    /** See {@link AuditActions}. */
    private String actionType;

    private String bizType;
    private String bizId;
    private String beforeValue;
    private String afterValue;
    private String ipAddress;

    /** Archive cut-off; set to three years after the action. */
    private LocalDate retainUntil;
}
