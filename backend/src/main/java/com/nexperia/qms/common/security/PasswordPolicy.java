package com.nexperia.qms.common.security;

/**
 * The one password rule the application enforces, shared by the two places a
 * password is set through the UI: a user changing their own, and an administrator
 * resetting someone else's.
 *
 * The length floor matches the administrative CLI (AdminPasswordCli). The ceiling
 * is not arbitrary: BCrypt only considers the first 72 bytes, so a longer password
 * would silently accept a longer string than it can distinguish.
 */
public final class PasswordPolicy {

    public static final int MIN_LENGTH = 8;
    public static final int MAX_LENGTH = 72;

    private PasswordPolicy() {
    }

    /** Throws with a message the user can act on; the caller maps it to 400. */
    public static void requireAcceptable(String rawPassword) {
        if (rawPassword == null || rawPassword.length() < MIN_LENGTH) {
            throw new IllegalArgumentException("口令长度不能少于 " + MIN_LENGTH + " 个字符");
        }
        if (rawPassword.length() > MAX_LENGTH) {
            throw new IllegalArgumentException("口令长度不能超过 " + MAX_LENGTH + " 个字符");
        }
    }
}
