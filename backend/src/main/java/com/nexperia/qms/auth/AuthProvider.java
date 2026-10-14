package com.nexperia.qms.auth;

import java.util.Optional;

/**
 * Where credentials are verified. Phase 1 ships {@link LocalPasswordAuthProvider};
 * phase 2 adds the company OAuth2/SSO provider behind the same interface, so
 * nothing above this boundary changes.
 */
public interface AuthProvider {

    /** Human-readable name, used in logs and the /api/auth/me response. */
    String name();

    /** Whether this provider is the active one for the current configuration. */
    boolean isEnabled();

    /**
     * Verifies credentials.
     *
     * @return the employee id on success, or empty when the credentials are wrong
     * @throws org.springframework.security.authentication.LockedException when the account is locked
     */
    Optional<String> authenticate(String username, String rawPassword);
}
