package com.nexperia.qms.common.security;

import java.util.Set;

/**
 * The authenticated principal. {@code employeeId} is the single identifier used
 * everywhere in the schema (created_by / owner_id / operator), which is what lets
 * a future OAuth2/SSO provider drop in without touching business code.
 *
 * Roles and permissions are filled from the database on every request (see
 * {@link PermissionCache}), not from the token, so a permission change applies to
 * a session that is already open (requirement 3.12, PS-111 AC3).
 */
public record CurrentUser(
        String employeeId,
        String username,
        Set<String> roles,
        Set<String> permissions,
        boolean mustChangePwd) {

    public boolean can(String permission) {
        return permissions.contains(permission);
    }
}
