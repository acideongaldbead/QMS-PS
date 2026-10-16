package com.nexperia.qms.admin.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * Response and request shapes for the RBAC administration screens
 * (requirement 3.12): users, roles and the permission matrix.
 *
 * Grouped in one holder so the whole contract is visible in a single file, and so
 * the mapper's row projections sit next to the API shapes they are built from.
 */
public final class AdminDtos {

    private AdminDtos() {
    }

    // ------------------------------------------------------------------ users

    /**
     * One row of the user list: the employee, their account flags and the roles
     * they hold. {@code username} and the three account flags are null when the
     * employee has no account yet -- they can still be given roles, because the
     * assignment lives on the employee, not on the account.
     */
    public record UserView(
            String employeeId,
            String name,
            String nameEn,
            String deptL1,
            String deptL2,
            String jobTitle,
            String email,
            String username,
            Boolean accountActive,
            boolean locked,
            Boolean mustChangePwd,
            List<String> roleCodes) {
    }

    /**
     * The mapper projection behind {@link UserView}. Roles arrive as a
     * comma-separated string because that is what one row can carry; the service
     * splits it. Column order matches the select list.
     */
    public record UserRow(
            String employeeId,   //  1
            String name,         //  2
            String nameEn,       //  3
            String deptL1,       //  4
            String deptL2,       //  5
            String jobTitle,     //  6
            String email,        //  7
            String username,     //  8
            Boolean accountActive, //  9
            boolean locked,      // 10
            Boolean mustChangePwd, // 11
            String roleCodes) {  // 12
    }

    /** Replaces an employee's whole role set. */
    public record AssignRolesRequest(List<@NotBlank String> roleCodes) {
    }

    /** A temporary password the administrator hands over; the user must change it. */
    public record ResetPasswordRequest(
            @NotBlank(message = "口令不能为空")
            @Size(max = 72, message = "口令不能超过 72 个字符")
            String newPassword) {
    }

    // ------------------------------------------------------------------ roles

    /** One row of the role list. */
    public record RoleView(
            long roleId,
            String roleCode,
            String roleName,
            String roleNameEn,
            String roleType,
            boolean isActive,
            long userCount,
            List<Long> permissionIds) {
    }

    /** The mapper projection behind {@link RoleView}; permission ids as a string. */
    public record RoleRow(
            long roleId,        // 1
            String roleCode,    // 2
            String roleName,    // 3
            String roleNameEn,  // 4
            String roleType,    // 5
            boolean isActive,   // 6
            long userCount,     // 7
            String permissionIds) { // 8
    }

    /** The identity of a role, for the guard rails that must inspect it first. */
    public record RoleHeader(
            long roleId,
            String roleCode,
            String roleName,
            String roleNameEn,
            String roleType,
            boolean isActive) {
    }

    /** Create and rename share one shape; the role id comes from the path. */
    public record SaveRoleRequest(
            @NotBlank(message = "角色名称不能为空")
            @Size(max = 64, message = "角色名称不能超过 64 个字符")
            String roleName,
            @Size(max = 64, message = "角色英文名不能超过 64 个字符")
            String roleNameEn,
            List<Long> permissionIds) {
    }

    /** Copy: names the new role, or leaves it to be derived from the source. */
    public record CopyRoleRequest(
            @Size(max = 64, message = "角色名称不能超过 64 个字符")
            String roleName) {
    }

    /** Replaces a role's whole permission set. */
    public record RolePermissionsRequest(List<Long> permissionIds) {
    }

    // ------------------------------------------------------------ permissions

    /** One permission, as the matrix renders it. */
    public record PermissionView(
            long permissionId,
            String permissionCode,
            String permissionName,
            String permissionNameEn,
            String permissionLevel,
            String moduleCode) {
    }

    // ----------------------------------------------------------------- export

    /** One line of the exported matrix: a role x permission pair. */
    public record MatrixCell(
            String roleName,
            String roleType,
            String moduleCode,
            String permissionCode,
            String permissionName,
            String permissionLevel,
            boolean granted) {
    }
}
