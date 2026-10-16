package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
import com.nexperia.qms.admin.mapper.AdminMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.common.security.PasswordPolicy;
import com.nexperia.qms.common.security.PermissionCache;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * User administration (requirement 3.12): who is in the system, which roles they
 * hold, and whether their account is usable.
 *
 * Role assignment is the many-to-many {@code user_role}: any role -- including the
 * four preset ones, administrator included -- can be held by any number of
 * employees. Employees without an account can still be given roles; only the
 * account actions need an account to act on.
 */
@Service
public class AdminUserService {

    private static final String BIZ_USER_ROLE = "UserRole";
    private static final String BIZ_ACCOUNT = "UserAccount";
    private static final String ADMIN_ROLE_CODE = "ROLE_ADMINISTRATOR";

    private final AdminMapper adminMapper;
    private final AuditLogService auditLogService;
    private final PermissionCache permissionCache;
    private final PasswordEncoder passwordEncoder;

    public AdminUserService(AdminMapper adminMapper,
                            AuditLogService auditLogService,
                            PermissionCache permissionCache,
                            PasswordEncoder passwordEncoder) {
        this.adminMapper = adminMapper;
        this.auditLogService = auditLogService;
        this.permissionCache = permissionCache;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional(readOnly = true)
    public List<AdminDtos.UserView> list() {
        List<AdminDtos.UserView> users = new ArrayList<>();
        for (AdminDtos.UserRow row : adminMapper.findUsers()) {
            users.add(new AdminDtos.UserView(
                    row.employeeId(), row.name(), row.nameEn(), row.deptL1(), row.deptL2(),
                    row.jobTitle(), row.email(), row.username(), row.accountActive(),
                    row.locked(), row.mustChangePwd(), splitCodes(row.roleCodes())));
        }
        return users;
    }

    /** Replaces an employee's whole role set with the one supplied. */
    @Transactional
    public void assignRoles(String employeeId, AdminDtos.AssignRolesRequest request) {
        requireEmployee(employeeId);
        String operator = requireOperator();

        List<String> wanted = distinctCodes(request == null ? null : request.roleCodes());
        List<Long> targetIds = wanted.isEmpty() ? List.of() : adminMapper.findAssignableRoleIds(wanted);
        if (targetIds.size() != wanted.size()) {
            throw new IllegalArgumentException("角色不存在、已删除或已停用");
        }

        Set<Long> current = new HashSet<>(adminMapper.findRoleIdsOfUser(employeeId));
        Set<Long> target = new HashSet<>(targetIds);
        if (current.equals(target)) {
            return;
        }

        requireAdministratorRemains(employeeId, operator, current, target);

        List<String> before = adminMapper.findRoleCodesOfUser(employeeId);
        for (Long roleId : current) {
            if (!target.contains(roleId)) {
                adminMapper.deleteUserRole(employeeId, roleId);
            }
        }
        for (Long roleId : target) {
            if (!current.contains(roleId)) {
                adminMapper.insertUserRole(employeeId, roleId, operator);
            }
        }

        List<String> after = new ArrayList<>(wanted);
        after.sort(String::compareTo);
        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_USER_ROLE, employeeId,
                String.join(",", before), String.join(",", after));
        permissionCache.invalidateAfterCommit(employeeId);
    }

    @Transactional
    public void setAccountActive(String employeeId, boolean active) {
        requireEmployee(employeeId);
        String operator = requireOperator();

        if (!active) {
            if (employeeId.equals(operator)) {
                throw new IllegalStateException("不能停用自己的账号");
            }
            if (adminMapper.countAdministratorRoles(employeeId) > 0 && adminMapper.countAdministrators() <= 1) {
                throw new IllegalStateException("系统必须至少保留一名可登录的管理员");
            }
        }

        if (adminMapper.updateAccountActive(employeeId, active, operator) == 0) {
            throw new NotFoundException("该员工没有账号：" + employeeId);
        }
        auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, BIZ_ACCOUNT, employeeId,
                active ? "停用" : "启用", active ? "启用" : "停用");
        // Both directions need it: enabling must clear a cached "inactive" too.
        permissionCache.invalidateAfterCommit(employeeId);
    }

    /** Sets a temporary password and forces the user to change it at next sign-in. */
    @Transactional
    public void resetPassword(String employeeId, AdminDtos.ResetPasswordRequest request) {
        requireEmployee(employeeId);
        PasswordPolicy.requireAcceptable(request.newPassword());
        String operator = requireOperator();

        int updated = adminMapper.resetPassword(employeeId,
                passwordEncoder.encode(request.newPassword()), operator);
        if (updated == 0) {
            throw new NotFoundException("该员工没有账号：" + employeeId);
        }
        auditLogService.record(AuditActions.PASSWORD_RESET, BIZ_ACCOUNT, employeeId,
                "管理员重置登录口令，已要求该用户下次登录时修改");
        permissionCache.invalidateAfterCommit(employeeId);
    }

    @Transactional
    public void unlock(String employeeId) {
        requireEmployee(employeeId);
        String operator = requireOperator();

        if (adminMapper.clearAccountLock(employeeId, operator) == 0) {
            throw new NotFoundException("该员工没有账号：" + employeeId);
        }
        auditLogService.record(AuditActions.UNLOCK, BIZ_ACCOUNT, employeeId, "清除登录锁定与失败次数");
    }

    /**
     * Removing an administrator role is allowed, ending up with none is not.
     * Without this the last administrator could demote themselves out of the
     * screen that manages roles, and nobody could give the role back.
     */
    private void requireAdministratorRemains(String employeeId, String operator,
                                             Set<Long> current, Set<Long> target) {
        Long adminRoleId = adminMapper.findRoleIdByCode(ADMIN_ROLE_CODE);
        if (adminRoleId == null || !current.contains(adminRoleId) || target.contains(adminRoleId)) {
            return;
        }
        if (employeeId.equals(operator)) {
            throw new IllegalStateException("不能移除自己的管理员角色");
        }
        if (adminMapper.countAdministrators() <= 1) {
            throw new IllegalStateException("系统必须至少保留一名管理员");
        }
    }

    private void requireEmployee(String employeeId) {
        if (adminMapper.countEmployee(employeeId) == 0) {
            throw new NotFoundException("员工不存在：" + employeeId);
        }
    }

    private static List<String> splitCodes(String csv) {
        if (csv == null || csv.isBlank()) {
            return List.of();
        }
        return Arrays.stream(csv.split(",")).map(String::trim).filter(s -> !s.isEmpty()).toList();
    }

    private static List<String> distinctCodes(List<String> codes) {
        Set<String> out = new LinkedHashSet<>();
        if (codes != null) {
            for (String code : codes) {
                if (code != null && !code.isBlank()) {
                    out.add(code.trim());
                }
            }
        }
        return new ArrayList<>(out);
    }

    private static String requireOperator() {
        String operator = CurrentUserContext.employeeId();
        if (operator == null) {
            throw new IllegalStateException("未登录或登录已过期");
        }
        return operator;
    }
}
