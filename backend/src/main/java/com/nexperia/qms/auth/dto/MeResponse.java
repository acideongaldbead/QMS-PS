package com.nexperia.qms.auth.dto;

import java.util.List;

/** Shape matches CurrentUser in frontend/src/stores/auth.ts. */
public record MeResponse(
        String employeeId,
        String username,
        String name,
        String nameEn,
        String email,
        String deptL1,
        String deptL2,
        String jobTitle,
        List<String> roles,
        List<String> permissions) {
}
