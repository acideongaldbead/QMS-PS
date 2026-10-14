package com.nexperia.qms.common.audit;

import com.nexperia.qms.common.audit.mapper.AuditLogMapper;
import com.nexperia.qms.common.security.CurrentUserContext;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.time.LocalDate;

/**
 * Writes audit rows.
 *
 * Called explicitly from the services that perform auditable actions rather than
 * through a generic AOP interceptor: the set of actions is small and known, and an
 * explicit call is easier to read and to test. If the call sites ever grow past a
 * handful, an aspect can wrap this service without changing the callers.
 *
 * Always call inside the transaction of the action being audited, so a failed
 * action leaves no audit row and a committed action always has one.
 */
@Service
public class AuditLogService {

    private static final Logger log = LoggerFactory.getLogger(AuditLogService.class);

    /** Requirement 3.16: audit records are retained for at least three years. */
    private static final int RETENTION_YEARS = 3;

    private final AuditLogMapper auditLogMapper;

    public AuditLogService(AuditLogMapper auditLogMapper) {
        this.auditLogMapper = auditLogMapper;
    }

    /**
     * Records an event that must survive the caller's rollback.
     *
     * A refused action is exactly the kind of event a security review needs, but
     * the refusal is signalled by throwing, which rolls the caller's transaction
     * back -- taking any audit row written inside it. Running in its own
     * transaction makes the entry durable on its own.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordRegardlessOfOutcome(String actionType, String bizType, String bizId, String detail) {
        record(actionType, bizType, bizId, detail);
    }

    public void record(String actionType, String bizType, String bizId, String detail) {
        try {
            AuditLog entry = new AuditLog();
            entry.setOperatorId(CurrentUserContext.employeeId());
            entry.setActionType(actionType);
            entry.setBizType(bizType);
            entry.setBizId(bizId);
            entry.setAfterValue(detail);
            entry.setIpAddress(currentIpAddress());
            entry.setRetainUntil(LocalDate.now().plusYears(RETENTION_YEARS));
            auditLogMapper.insert(entry);
        } catch (RuntimeException e) {
            // An audit write must never take down the business action, but it must
            // be loud: silent loss would undermine the whole audit requirement.
            log.error("Failed to write audit log: action={} bizType={} bizId={}",
                    actionType, bizType, bizId, e);
        }
    }

    public void recordValueChange(String actionType, String bizType, String bizId,
                                  String beforeValue, String afterValue) {
        try {
            AuditLog entry = new AuditLog();
            entry.setOperatorId(CurrentUserContext.employeeId());
            entry.setActionType(actionType);
            entry.setBizType(bizType);
            entry.setBizId(bizId);
            entry.setBeforeValue(beforeValue);
            entry.setAfterValue(afterValue);
            entry.setIpAddress(currentIpAddress());
            entry.setRetainUntil(LocalDate.now().plusYears(RETENTION_YEARS));
            auditLogMapper.insert(entry);
        } catch (RuntimeException e) {
            log.error("Failed to write audit log: action={} bizType={} bizId={}",
                    actionType, bizType, bizId, e);
        }
    }

    private String currentIpAddress() {
        try {
            var attributes = RequestContextHolder.getRequestAttributes();
            if (attributes instanceof ServletRequestAttributes servletAttributes) {
                HttpServletRequest request = servletAttributes.getRequest();
                String forwarded = request.getHeader("X-Forwarded-For");
                if (forwarded != null && !forwarded.isBlank()) {
                    return forwarded.split(",")[0].trim();
                }
                return request.getRemoteAddr();
            }
        } catch (RuntimeException e) {
            log.debug("Could not resolve client IP", e);
        }
        return null;
    }
}
