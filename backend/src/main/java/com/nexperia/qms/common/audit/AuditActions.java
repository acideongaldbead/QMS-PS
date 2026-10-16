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

    /** An administrator reset someone else's password (requirement 3.12). */
    public static final String PASSWORD_RESET = "PASSWORD_RESET";

    /** A user changed their own password, including the forced first change. */
    public static final String PASSWORD_CHANGE = "PASSWORD_CHANGE";

    /** A login lockout was cleared by an administrator. */
    public static final String UNLOCK = "UNLOCK";

    /**
     * A request refused because the caller lacked the permission it needs
     * (requirement 3.12, PS-113 AC3). Own action type so an audit review can
     * filter refused attempts out of the ordinary traffic.
     */
    public static final String ACCESS_DENIED = "ACCESS_DENIED";

    private AuditActions() {
    }
}
