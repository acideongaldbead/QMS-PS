package com.nexperia.qms.common.persistence;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableLogic;
import lombok.Data;

import java.time.OffsetDateTime;

/**
 * The audit columns every table in the schema carries.
 *
 * {@code created_at} / {@code created_by} and {@code updated_by} are filled from
 * the logged-in user by {@link QmsMetaObjectHandler}. {@code updated_at} is
 * deliberately NOT filled here: every table already has a BEFORE UPDATE trigger
 * maintaining it, and writing it from two places would make the value depend on
 * which one ran last.
 *
 * {@code @TableLogic} makes MyBatis-Plus append {@code is_deleted = false} to
 * every generated query and turn deletes into updates, which matches the partial
 * indexes in the schema.
 */
@Data
public abstract class BaseEntity {

    @TableField(value = "created_at", fill = FieldFill.INSERT)
    private OffsetDateTime createdAt;

    @TableField(value = "created_by", fill = FieldFill.INSERT)
    private String createdBy;

    @TableField(value = "updated_by", fill = FieldFill.INSERT_UPDATE)
    private String updatedBy;

    @TableLogic
    @TableField("is_deleted")
    private Boolean isDeleted;
}
