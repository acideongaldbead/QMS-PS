package com.nexperia.qms.auth;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.OffsetDateTime;

/** Row of {@code user_account} (added by migration V2). */
@Data
@TableName("user_account")
public class UserAccount {

    @TableId(value = "account_id", type = IdType.AUTO)
    private Long accountId;

    private String employeeId;
    private String username;
    private String passwordHash;
    private Boolean isActive;
    private Integer failedAttempts;
    private OffsetDateTime lockedUntil;
    private OffsetDateTime lastLoginAt;
}
