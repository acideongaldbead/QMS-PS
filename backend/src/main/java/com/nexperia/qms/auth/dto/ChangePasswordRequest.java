package com.nexperia.qms.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** A user changing their own password (requirement 3.12). */
public record ChangePasswordRequest(
        @NotBlank(message = "当前口令不能为空") String oldPassword,
        @NotBlank(message = "新口令不能为空") String newPassword) {
}
