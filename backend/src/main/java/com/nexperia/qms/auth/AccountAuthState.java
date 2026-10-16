package com.nexperia.qms.auth;

/**
 * The two account flags the authorization path needs, read once per cache miss.
 * {@code active} is {@code user_account.is_active}; {@code mustChangePwd} is the
 * forced-change flag set by an administrator's password reset.
 */
public record AccountAuthState(boolean active, boolean mustChangePwd) {
}
