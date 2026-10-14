package com.nexperia.qms.common.security;

/**
 * Per-request holder for the authenticated user, so audit fields and service
 * methods can read it without threading it through every signature.
 * Populated and cleared by {@link JwtAuthFilter}.
 */
public final class CurrentUserContext {

    private static final ThreadLocal<CurrentUser> HOLDER = new ThreadLocal<>();

    private CurrentUserContext() {
    }

    public static void set(CurrentUser user) {
        HOLDER.set(user);
    }

    public static CurrentUser get() {
        return HOLDER.get();
    }

    public static String employeeId() {
        CurrentUser user = HOLDER.get();
        return user == null ? null : user.employeeId();
    }

    public static void clear() {
        HOLDER.remove();
    }
}
