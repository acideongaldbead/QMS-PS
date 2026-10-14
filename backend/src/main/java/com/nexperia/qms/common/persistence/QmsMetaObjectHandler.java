package com.nexperia.qms.common.persistence;

import com.baomidou.mybatisplus.core.handlers.MetaObjectHandler;
import com.nexperia.qms.common.security.CurrentUserContext;
import org.apache.ibatis.reflection.MetaObject;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;

/**
 * Stamps the audit columns with the current user. Runs for every insert/update
 * through MyBatis-Plus, so services never set these fields by hand.
 */
@Component
public class QmsMetaObjectHandler implements MetaObjectHandler {

    @Override
    public void insertFill(MetaObject metaObject) {
        String operator = CurrentUserContext.employeeId();
        OffsetDateTime now = OffsetDateTime.now();
        strictInsertFill(metaObject, "createdAt", OffsetDateTime.class, now);
        strictInsertFill(metaObject, "createdBy", String.class, operator);
        // Populated on insert too, so "last modified by" is never blank on a fresh row.
        strictInsertFill(metaObject, "updatedBy", String.class, operator);
    }

    @Override
    public void updateFill(MetaObject metaObject) {
        strictUpdateFill(metaObject, "updatedBy", String.class, CurrentUserContext.employeeId());
    }
}
