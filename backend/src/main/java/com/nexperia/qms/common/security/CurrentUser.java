package com.nexperia.qms.common.security;

import java.util.Set;

/**
 * The authenticated principal. {@code employeeId} is the single identifier used
 * everywhere in the schema (created_by / owner_id / operator), which is what lets
 * a future OAuth2/SSO provider drop in without touching business code.
 */
public record CurrentUser(
        String employeeId,
        String username,
        Set<String> roles,
        Set<String> permissions) {

    public boolean can(String permission) {
        return permissions.contains(permission);
    }
}
