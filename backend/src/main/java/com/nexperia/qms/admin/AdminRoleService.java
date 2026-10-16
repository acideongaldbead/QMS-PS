package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
import com.nexperia.qms.admin.mapper.AdminMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.common.security.PermissionCache;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Role administration and the permission matrix (requirement 3.12).
 *
 * The four preset roles are read-only: they cannot be renamed, disabled, deleted
 * or have their permissions edited, and every such attempt is refused with 409.
 * They can be copied, which is how a variant is meant to be made -- that is what
 * PS-112 AC3 asks for.
 *
 * Any change here can move permissions for many people at once, so every write
 * flushes the whole authorization cache rather than one entry.
 */
@Service
public class AdminRoleService {

    private static final String BIZ_ROLE = "Role";
    private static final String PRESET = "PRESET";
    private static final String CUSTOM = "CUSTOM";
    private static final int MAX_NAME_LENGTH = 64;
    private static final String COPY_SUFFIX = "-副本";

    private final AdminMapper adminMapper;
    private final AuditLogService auditLogService;
    private final PermissionCache permissionCache;
    private final MatrixExcelWriter matrixExcelWriter;

    public AdminRoleService(AdminMapper adminMapper,
                            AuditLogService auditLogService,
                            PermissionCache permissionCache,
                            MatrixExcelWriter matrixExcelWriter) {
        this.adminMapper = adminMapper;
        this.auditLogService = auditLogService;
        this.permissionCache = permissionCache;
        this.matrixExcelWriter = matrixExcelWriter;
    }

    @Transactional(readOnly = true)
    public List<AdminDtos.RoleView> list() {
        return adminMapper.findRoles(null).stream().map(AdminRoleService::toView).toList();
    }

    @Transactional(readOnly = true)
    public AdminDtos.RoleView get(long roleId) {
        return toView(requireRow(roleId));
    }

    @Transactional(readOnly = true)
    public List<AdminDtos.PermissionView> permissions() {
        return adminMapper.findPermissions();
    }

    @Transactional
    public AdminDtos.RoleView create(AdminDtos.SaveRoleRequest request) {
        String operator = requireOperator();
        String name = requireName(request.roleName());
        requireRoleNameFree(name, null);

        long roleId = adminMapper.insertCustomRole(name, trimToNull(request.roleNameEn()), operator);
        int granted = applyPermissions(roleId, request.permissionIds(), operator);
        auditLogService.record(AuditActions.CREATE, BIZ_ROLE, String.valueOf(roleId),
                "新建自定义角色：" + name + "，勾选权限 " + granted + " 项");
        permissionCache.invalidateAllAfterCommit();
        return get(roleId);
    }

    @Transactional
    public AdminDtos.RoleView rename(long roleId, AdminDtos.SaveRoleRequest request) {
        AdminDtos.RoleHeader role = requireRole(roleId);
        requireCustom(role, "预设角色不能修改");
        String operator = requireOperator();
        String name = requireName(request.roleName());
        requireRoleNameFree(name, roleId);

        String nameEn = trimToNull(request.roleNameEn());
        adminMapper.updateRoleName(roleId, name, nameEn, operator);
        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_ROLE, String.valueOf(roleId),
                describeName(role.roleName(), role.roleNameEn()), describeName(name, nameEn));
        permissionCache.invalidateAllAfterCommit();
        return get(roleId);
    }

    @Transactional
    public void delete(long roleId) {
        AdminDtos.RoleHeader role = requireRole(roleId);
        requireCustom(role, "预设角色不能删除");
        if (adminMapper.countUsersOfRole(roleId) > 0) {
            throw new IllegalStateException("该角色仍有用户在使用，不能删除");
        }
        adminMapper.softDeleteRole(roleId, requireOperator());
        auditLogService.record(AuditActions.DELETE, BIZ_ROLE, String.valueOf(roleId),
                "删除自定义角色：" + role.roleName());
        permissionCache.invalidateAllAfterCommit();
    }

    @Transactional
    public AdminDtos.RoleView copy(long roleId, AdminDtos.CopyRoleRequest request) {
        AdminDtos.RoleHeader source = requireRole(roleId);
        String operator = requireOperator();
        String name = resolveCopyName(source.roleName(), request == null ? null : request.roleName());

        long newRoleId = adminMapper.insertCustomRole(name, source.roleNameEn(), operator);
        int copied = adminMapper.copyRolePermissions(roleId, newRoleId, operator);
        auditLogService.record(AuditActions.CREATE, BIZ_ROLE, String.valueOf(newRoleId),
                "复制角色：" + source.roleName() + " -> " + name + "，继承权限 " + copied + " 项");
        permissionCache.invalidateAllAfterCommit();
        return get(newRoleId);
    }

    @Transactional
    public AdminDtos.RoleView setActive(long roleId, boolean active) {
        AdminDtos.RoleHeader role = requireRole(roleId);
        requireCustom(role, "预设角色不能停用或启用");
        if (role.isActive() == active) {
            return get(roleId);
        }
        adminMapper.updateRoleActive(roleId, active, requireOperator());
        auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, BIZ_ROLE, String.valueOf(roleId),
                role.isActive() ? "启用" : "停用", active ? "启用" : "停用");
        // Disabling a role has to take its permissions away immediately.
        permissionCache.invalidateAllAfterCommit();
        return get(roleId);
    }

    @Transactional
    public AdminDtos.RoleView replacePermissions(long roleId, AdminDtos.RolePermissionsRequest request) {
        AdminDtos.RoleHeader role = requireRole(roleId);
        requireCustom(role, "预设角色的权限不能修改");
        String operator = requireOperator();

        Map<Long, String> codeById = permissionCodes();
        List<String> before = codesOf(adminMapper.findPermissionIdsOfRole(roleId), codeById);
        applyPermissions(roleId, request == null ? null : request.permissionIds(), operator);
        List<String> after = codesOf(adminMapper.findPermissionIdsOfRole(roleId), codeById);

        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_ROLE, String.valueOf(roleId),
                String.join(",", before), String.join(",", after));
        permissionCache.invalidateAllAfterCommit();
        return get(roleId);
    }

    /** PS-113 AC2: the matrix as a workbook, one line per role x permission pair. */
    @Transactional
    public byte[] exportMatrix() {
        List<AdminDtos.RoleRow> roles = adminMapper.findRoles(null);
        List<AdminDtos.PermissionView> permissions = adminMapper.findPermissions();

        List<AdminDtos.MatrixCell> cells = new ArrayList<>(roles.size() * permissions.size());
        for (AdminDtos.RoleRow role : roles) {
            Set<Long> granted = new HashSet<>(parseIds(role.permissionIds()));
            for (AdminDtos.PermissionView permission : permissions) {
                cells.add(new AdminDtos.MatrixCell(
                        role.roleName(), role.roleType(), permission.moduleCode(),
                        permission.permissionCode(), permission.permissionName(),
                        permission.permissionLevel(), granted.contains(permission.permissionId())));
            }
        }

        // A writable transaction, like the ledger export: an audit row cannot be
        // inserted on a read-only connection.
        auditLogService.record(AuditActions.EXPORT, BIZ_ROLE, null,
                "导出权限矩阵：" + roles.size() + " 个角色 x " + permissions.size() + " 项权限，共 "
                        + cells.size() + " 行");
        return matrixExcelWriter.toWorkbook(cells);
    }

    // ------------------------------------------------------------------ helpers

    /** Diffs the stored links against the requested set; returns how many are granted. */
    private int applyPermissions(long roleId, List<Long> requestedIds, String operator) {
        List<Long> target = distinctIds(requestedIds);
        if (!target.isEmpty() && adminMapper.countLivePermissions(target) != target.size()) {
            throw new IllegalArgumentException("权限不存在或已删除");
        }
        Set<Long> current = new HashSet<>(adminMapper.findPermissionIdsOfRole(roleId));
        Set<Long> wanted = new HashSet<>(target);
        for (Long id : current) {
            if (!wanted.contains(id)) {
                adminMapper.deleteRolePermission(roleId, id);
            }
        }
        for (Long id : target) {
            if (!current.contains(id)) {
                adminMapper.insertRolePermission(roleId, id, operator);
            }
        }
        return target.size();
    }

    /**
     * The name for a copy: the caller's when supplied, otherwise the source name
     * with a suffix, numbered until it is free. Role names are capped at 64
     * characters, so the base is shortened to leave room for the suffix.
     */
    private String resolveCopyName(String sourceName, String requested) {
        if (requested != null && !requested.isBlank()) {
            String name = requireName(requested);
            requireRoleNameFree(name, null);
            return name;
        }
        String candidate = withSuffix(sourceName, COPY_SUFFIX);
        if (adminMapper.countRoleByName(candidate, null) == 0) {
            return candidate;
        }
        for (int n = 2; n <= 99; n++) {
            candidate = withSuffix(sourceName, COPY_SUFFIX + n);
            if (adminMapper.countRoleByName(candidate, null) == 0) {
                return candidate;
            }
        }
        throw new IllegalStateException("无法为副本生成唯一名称，请指定角色名称");
    }

    private static String withSuffix(String base, String suffix) {
        String stem = base.length() + suffix.length() > MAX_NAME_LENGTH
                ? base.substring(0, MAX_NAME_LENGTH - suffix.length())
                : base;
        return stem + suffix;
    }

    private static void requireCustom(AdminDtos.RoleHeader role, String message) {
        if (!CUSTOM.equals(role.roleType())) {
            throw new IllegalStateException(message);
        }
    }

    private void requireRoleNameFree(String name, Long excludeId) {
        if (adminMapper.countRoleByName(name, excludeId) > 0) {
            throw new IllegalStateException("角色名称已存在：" + name);
        }
    }

    /** Trimmed and length-checked; the bean-validation copy covers the request body. */
    private static String requireName(String raw) {
        String name = trimToNull(raw);
        if (name == null) {
            throw new IllegalArgumentException("角色名称不能为空");
        }
        if (name.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException("角色名称不能超过 " + MAX_NAME_LENGTH + " 个字符");
        }
        return name;
    }

    private AdminDtos.RoleHeader requireRole(long roleId) {
        AdminDtos.RoleHeader role = adminMapper.findRoleHeader(roleId);
        if (role == null) {
            throw new NotFoundException("角色不存在：" + roleId);
        }
        return role;
    }

    private AdminDtos.RoleRow requireRow(long roleId) {
        List<AdminDtos.RoleRow> rows = adminMapper.findRoles(roleId);
        if (rows.isEmpty()) {
            throw new NotFoundException("角色不存在：" + roleId);
        }
        return rows.get(0);
    }

    private Map<Long, String> permissionCodes() {
        Map<Long, String> codes = new HashMap<>();
        for (AdminDtos.PermissionView permission : adminMapper.findPermissions()) {
            codes.put(permission.permissionId(), permission.permissionCode());
        }
        return codes;
    }

    private static List<String> codesOf(List<Long> ids, Map<Long, String> codeById) {
        List<String> codes = new ArrayList<>();
        for (Long id : ids) {
            String code = codeById.get(id);
            codes.add(code == null ? String.valueOf(id) : code);
        }
        codes.sort(String::compareTo);
        return codes;
    }

    private static AdminDtos.RoleView toView(AdminDtos.RoleRow row) {
        return new AdminDtos.RoleView(
                row.roleId(), row.roleCode(), row.roleName(), row.roleNameEn(),
                row.roleType(), row.isActive(), row.userCount(), parseIds(row.permissionIds()));
    }

    private static List<Long> parseIds(String csv) {
        if (csv == null || csv.isBlank()) {
            return List.of();
        }
        List<Long> ids = new ArrayList<>();
        for (String part : csv.split(",")) {
            String value = part.trim();
            if (!value.isEmpty()) {
                ids.add(Long.valueOf(value));
            }
        }
        return ids;
    }

    private static List<Long> distinctIds(List<Long> ids) {
        Set<Long> out = new LinkedHashSet<>();
        if (ids != null) {
            for (Long id : ids) {
                if (id != null) {
                    out.add(id);
                }
            }
        }
        return new ArrayList<>(out);
    }

    private static String describeName(String name, String nameEn) {
        return "名称=" + name + "；英文名=" + (nameEn == null || nameEn.isBlank() ? "-" : nameEn);
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String requireOperator() {
        String operator = CurrentUserContext.employeeId();
        if (operator == null) {
            throw new IllegalStateException("未登录或登录已过期");
        }
        return operator;
    }
}
