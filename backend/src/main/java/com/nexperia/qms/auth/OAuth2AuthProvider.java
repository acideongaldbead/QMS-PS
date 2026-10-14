package com.nexperia.qms.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * Reserved swap point for the company OAuth2 / SSO provider (requirement 3.16,
 * PS-114). Disabled by default; phase 2 implements the authorization-code exchange
 * and maps the SSO subject to {@code employee.employee_id}. It is a deliberately
 * inert placeholder so the wiring exists and no business code changes later.
 */
@Component
public class OAuth2AuthProvider implements AuthProvider {

    private final boolean enabled;

    public OAuth2AuthProvider(@Value("${qms.auth.sso.enabled:false}") boolean enabled) {
        this.enabled = enabled;
    }

    @Override
    public String name() {
        return "oauth2";
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }

    @Override
    public Optional<String> authenticate(String username, String rawPassword) {
        throw new UnsupportedOperationException(
                "OAuth2/SSO is not implemented in phase 1; log in through the SSO redirect instead");
    }
}
