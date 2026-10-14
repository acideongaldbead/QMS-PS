package com.nexperia.qms.common.audit;

/** The action types written to audit_log, in one place so reports stay consistent. */
public final class AuditActions {

    public static final String LOGIN = "LOGIN";
    public static final String LOGIN_FAILED = "LOGIN_FAILED";
    public static final String CREATE = "CREATE";
    public static final String UPDATE = "UPDATE";
    public static final String DELETE = "DELETE";
    public static final String STATUS_CHANGE = "STATUS_CHANGE";
    public static final String EXPORT = "EXPORT";
    public static final String SEND = "SEND";
    public static final String APPROVE = "APPROVE";
    public static final String REJECT = "REJECT";

    /**
     * An upload refused by validation or scanning. It gets its own action type
     * rather than being a CREATE with a remark, so a security review can count
     * refusals with a plain equality filter.
     */
    public static final String UPLOAD_REJECTED = "UPLOAD_REJECTED";

    private AuditActions() {
    }
}
