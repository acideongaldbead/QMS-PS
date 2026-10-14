package com.nexperia.qms.auth.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.auth.EmployeeProfile;
import com.nexperia.qms.auth.UserAccount;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Auth queries. Permissions are resolved through the RBAC chain
 * user_role -> role_permission -> permission, all keys are the stable *_code
 * columns rather than display names.
 */
@Mapper
public interface AuthMapper extends BaseMapper<UserAccount> {

    @Select("""
            SELECT employee_id, name, name_en, email, dept_l1, dept_l2, job_title
              FROM employee
             WHERE employee_id = #{employeeId} AND is_deleted = false
            """)
    EmployeeProfile findProfile(@Param("employeeId") String employeeId);

    @Select("""
            SELECT r.role_code
              FROM user_role ur
              JOIN role r ON r.role_id = ur.role_id
             WHERE ur.employee_id = #{employeeId}
               AND ur.is_deleted = false
               AND r.is_deleted = false
               AND r.is_active = true
            """)
    List<String> findRoleCodes(@Param("employeeId") String employeeId);

    @Select("""
            SELECT DISTINCT p.permission_code
              FROM user_role ur
              JOIN role_permission rp ON rp.role_id = ur.role_id AND rp.is_deleted = false
              JOIN permission p ON p.permission_id = rp.permission_id AND p.is_deleted = false
             WHERE ur.employee_id = #{employeeId} AND ur.is_deleted = false
            """)
    List<String> findPermissionCodes(@Param("employeeId") String employeeId);

    @Update("""
            UPDATE user_account
               SET failed_attempts = 0, locked_until = NULL, last_login_at = now()
             WHERE account_id = #{accountId}
            """)
    int markLoginSuccess(@Param("accountId") Long accountId);

    @Update("""
            UPDATE user_account
               SET failed_attempts = #{failedAttempts}, locked_until = #{lockedUntil}
             WHERE account_id = #{accountId}
            """)
    int markLoginFailure(@Param("accountId") Long accountId,
                         @Param("failedAttempts") int failedAttempts,
                         @Param("lockedUntil") OffsetDateTime lockedUntil);

    @Select("SELECT password_hash FROM user_account WHERE account_id = #{accountId}")
    String findPasswordHash(@Param("accountId") Long accountId);

    /** Accounts still holding the seed sentinel password. */
    @Select("SELECT account_id FROM user_account WHERE password_hash = 'CHANGE_ME' AND is_deleted = false")
    List<Long> findAccountsWithPlaceholderPassword();

    @Update("UPDATE user_account SET password_hash = #{hash} WHERE account_id = #{accountId}")
    int setPasswordHash(@Param("accountId") Long accountId, @Param("hash") String hash);
}
