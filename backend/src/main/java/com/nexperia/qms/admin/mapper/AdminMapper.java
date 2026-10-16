package com.nexperia.qms.admin.mapper;

import com.nexperia.qms.admin.dto.AdminDtos;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

/**
 * Queries behind the RBAC administration screens (requirement 3.12).
 *
 * The RBAC tables have no MyBatis-Plus entities -- everything else in the project
 * reads them through hand-written SQL too -- so writes go through explicit
 * statements here rather than through an entity mapper.
 *
 * Row projections are records mapped by column position, so the select list order
 * must match the record's components; both sides are numbered to keep them aligned.
 *
 * The two association tables (user_role, role_permission) are edited by physical
 * delete: they are pure links with no meaning of their own, the change is recorded
 * in audit_log, and a physical delete is what keeps a plain UNIQUE constraint from
 * blocking a pair that was removed and then added back.
 */
@Mapper
public interface AdminMapper {

    // ------------------------------------------------------------------ users

    /**
     * Every live employee with their account flags and roles. Employees without an
     * account are included on purpose: the roles they would be given live on the
     * employee, and hiding them would make the screen silently incomplete.
     */
    @Select("""
            SELECT e.employee_id     AS employeeId,      --  1
                   e.name            AS name,            --  2
                   e.name_en         AS nameEn,          --  3
                   e.dept_l1         AS deptL1,          --  4
                   e.dept_l2         AS deptL2,          --  5
                   e.job_title       AS jobTitle,        --  6
                   e.email           AS email,           --  7
                   a.username        AS username,        --  8
                   a.is_active       AS accountActive,   --  9
                   (a.locked_until IS NOT NULL AND a.locked_until > now()) AS locked, -- 10
                   a.must_change_pwd AS mustChangePwd,   -- 11
                   (SELECT string_agg(r.role_code, ',' ORDER BY r.role_id)
                      FROM user_role ur
                      JOIN role r ON r.role_id = ur.role_id
                     WHERE ur.employee_id = e.employee_id
                       AND ur.is_deleted = false
                       AND r.is_deleted = false) AS roleCodes -- 12
              FROM employee e
              LEFT JOIN user_account a ON a.employee_id = e.employee_id AND a.is_deleted = false
             WHERE e.is_deleted = false
             ORDER BY e.employee_id
            """)
    List<AdminDtos.UserRow> findUsers();

    @Select("SELECT count(*) FROM employee WHERE employee_id = #{employeeId} AND is_deleted = false")
    int countEmployee(@Param("employeeId") String employeeId);

    @Select("""
            SELECT r.role_code
              FROM user_role ur
              JOIN role r ON r.role_id = ur.role_id
             WHERE ur.employee_id = #{employeeId}
               AND ur.is_deleted = false
               AND r.is_deleted = false
             ORDER BY r.role_id
            """)
    List<String> findRoleCodesOfUser(@Param("employeeId") String employeeId);

    @Select("SELECT role_id FROM user_role WHERE employee_id = #{employeeId} AND is_deleted = false")
    List<Long> findRoleIdsOfUser(@Param("employeeId") String employeeId);

    /** Only live, enabled roles can be assigned -- a disabled role is not offered. */
    @Select("""
            <script>
            SELECT role_id FROM role
             WHERE is_deleted = false AND is_active = true
               AND role_code IN
               <foreach item="code" collection="roleCodes" open="(" separator="," close=")">#{code}</foreach>
            </script>
            """)
    List<Long> findAssignableRoleIds(@Param("roleCodes") List<String> roleCodes);

    @Delete("DELETE FROM user_role WHERE employee_id = #{employeeId} AND role_id = #{roleId}")
    int deleteUserRole(@Param("employeeId") String employeeId, @Param("roleId") long roleId);

    @Insert("""
            INSERT INTO user_role (employee_id, role_id, effective_from, created_by, updated_by)
            VALUES (#{employeeId}, #{roleId}, now(), #{operator}, #{operator})
            """)
    int insertUserRole(@Param("employeeId") String employeeId,
                       @Param("roleId") long roleId,
                       @Param("operator") String operator);

    @Update("""
            UPDATE user_account
               SET is_active = #{active}, updated_by = #{operator}
             WHERE employee_id = #{employeeId} AND is_deleted = false
            """)
    int updateAccountActive(@Param("employeeId") String employeeId,
                            @Param("active") boolean active,
                            @Param("operator") String operator);

    /** A reset always flags the account for a forced change on the next sign-in. */
    @Update("""
            UPDATE user_account
               SET password_hash = #{hash},
                   must_change_pwd = true,
                   failed_attempts = 0,
                   locked_until = NULL,
                   updated_by = #{operator}
             WHERE employee_id = #{employeeId} AND is_deleted = false
            """)
    int resetPassword(@Param("employeeId") String employeeId,
                      @Param("hash") String hash,
                      @Param("operator") String operator);

    @Update("""
            UPDATE user_account
               SET failed_attempts = 0, locked_until = NULL, updated_by = #{operator}
             WHERE employee_id = #{employeeId} AND is_deleted = false
            """)
    int clearAccountLock(@Param("employeeId") String employeeId,
                         @Param("operator") String operator);

    // ------------------------------------------------------------------ roles

    /**
     * Preset roles first, then custom ones, so the list reads the way it is meant
     * to. {@code roleId} narrows it to one role, which is how a write returns the
     * row it just changed.
     */
    @Select("""
            <script>
            SELECT r.role_id     AS roleId,        -- 1
                   r.role_code   AS roleCode,      -- 2
                   r.role_name   AS roleName,      -- 3
                   r.role_name_en AS roleNameEn,   -- 4
                   r.role_type   AS roleType,      -- 5
                   r.is_active   AS isActive,      -- 6
                   (SELECT count(*) FROM user_role ur
                     WHERE ur.role_id = r.role_id AND ur.is_deleted = false) AS userCount, -- 7
                   (SELECT string_agg(rp.permission_id::text, ',' ORDER BY rp.permission_id)
                      FROM role_permission rp
                     WHERE rp.role_id = r.role_id AND rp.is_deleted = false) AS permissionIds -- 8
              FROM role r
             WHERE r.is_deleted = false
            <if test="roleId != null">
               AND r.role_id = #{roleId}
            </if>
             ORDER BY CASE WHEN r.role_type = 'PRESET' THEN 0 ELSE 1 END, r.role_id
            </script>
            """)
    List<AdminDtos.RoleRow> findRoles(@Param("roleId") Long roleId);

    @Select("""
            SELECT role_id, role_code, role_name, role_name_en, role_type, is_active
              FROM role
             WHERE role_id = #{roleId} AND is_deleted = false
            """)
    AdminDtos.RoleHeader findRoleHeader(@Param("roleId") long roleId);

    @Select("SELECT role_id FROM role WHERE role_code = #{roleCode} AND is_deleted = false")
    Long findRoleIdByCode(@Param("roleCode") String roleCode);

    @Select("""
            <script>
            SELECT count(*) FROM role
             WHERE is_deleted = false AND role_name = #{roleName}
            <if test="excludeId != null">
               AND role_id &lt;&gt; #{excludeId}
            </if>
            </script>
            """)
    int countRoleByName(@Param("roleName") String roleName, @Param("excludeId") Long excludeId);

    @Select("SELECT count(*) FROM user_role WHERE role_id = #{roleId} AND is_deleted = false")
    int countUsersOfRole(@Param("roleId") long roleId);

    /**
     * Allocates the id in the same statement that uses it, so the generated code is
     * stable ('ROLE_CUSTOM_&lt;id&gt;') and two concurrent creations cannot collide
     * on a placeholder. BY DEFAULT identity columns accept an explicit id, and the
     * nextval keeps the sequence ahead so later default inserts cannot reuse it.
     */
    @Select("""
            WITH allocated AS (
                SELECT nextval(pg_get_serial_sequence('qms.role', 'role_id')) AS new_role_id
            )
            INSERT INTO role (role_id, role_code, role_name, role_name_en, role_type, is_active,
                              created_by, updated_by, is_deleted)
            SELECT new_role_id,
                   'ROLE_CUSTOM_' || new_role_id,
                   #{roleName},
                   #{roleNameEn},
                   'CUSTOM',
                   true,
                   #{operator},
                   #{operator},
                   false
              FROM allocated
            RETURNING role_id
            """)
    long insertCustomRole(@Param("roleName") String roleName,
                          @Param("roleNameEn") String roleNameEn,
                          @Param("operator") String operator);

    @Update("""
            UPDATE role
               SET role_name = #{roleName}, role_name_en = #{roleNameEn}, updated_by = #{operator}
             WHERE role_id = #{roleId} AND is_deleted = false
            """)
    int updateRoleName(@Param("roleId") long roleId,
                       @Param("roleName") String roleName,
                       @Param("roleNameEn") String roleNameEn,
                       @Param("operator") String operator);

    @Update("UPDATE role SET is_active = #{active}, updated_by = #{operator} WHERE role_id = #{roleId}")
    int updateRoleActive(@Param("roleId") long roleId,
                         @Param("active") boolean active,
                         @Param("operator") String operator);

    @Update("UPDATE role SET is_deleted = true, updated_by = #{operator} WHERE role_id = #{roleId}")
    int softDeleteRole(@Param("roleId") long roleId, @Param("operator") String operator);

    @Select("SELECT permission_id FROM role_permission WHERE role_id = #{roleId} AND is_deleted = false")
    List<Long> findPermissionIdsOfRole(@Param("roleId") long roleId);

    @Delete("DELETE FROM role_permission WHERE role_id = #{roleId} AND permission_id = #{permissionId}")
    int deleteRolePermission(@Param("roleId") long roleId, @Param("permissionId") long permissionId);

    @Insert("""
            INSERT INTO role_permission (role_id, permission_id, created_by, updated_by)
            VALUES (#{roleId}, #{permissionId}, #{operator}, #{operator})
            """)
    int insertRolePermission(@Param("roleId") long roleId,
                             @Param("permissionId") long permissionId,
                             @Param("operator") String operator);

    @Insert("""
            INSERT INTO role_permission (role_id, permission_id, created_by, updated_by)
            SELECT #{targetRoleId}, rp.permission_id, #{operator}, #{operator}
              FROM role_permission rp
             WHERE rp.role_id = #{sourceRoleId} AND rp.is_deleted = false
            """)
    int copyRolePermissions(@Param("sourceRoleId") long sourceRoleId,
                            @Param("targetRoleId") long targetRoleId,
                            @Param("operator") String operator);

    // -------------------------------------------------------- administrator guard

    @Select("SELECT count(DISTINCT ur.employee_id) FROM user_role ur JOIN role r ON r.role_id = ur.role_id "
            + "WHERE r.role_code = 'ROLE_ADMINISTRATOR' AND r.is_deleted = false AND ur.is_deleted = false")
    int countAdministrators();

    @Select("SELECT count(*) FROM user_role ur JOIN role r ON r.role_id = ur.role_id "
            + "WHERE ur.employee_id = #{employeeId} AND r.role_code = 'ROLE_ADMINISTRATOR' "
            + "AND ur.is_deleted = false AND r.is_deleted = false")
    int countAdministratorRoles(@Param("employeeId") String employeeId);

    // ------------------------------------------------------------ permissions

    @Select("""
            SELECT p.permission_id     AS permissionId,     -- 1
                   p.permission_code   AS permissionCode,   -- 2
                   p.permission_name   AS permissionName,   -- 3
                   p.permission_name_en AS permissionNameEn, -- 4
                   p.permission_level  AS permissionLevel,  -- 5
                   p.module_code       AS moduleCode        -- 6
              FROM permission p
             WHERE p.is_deleted = false
             ORDER BY p.module_code NULLS LAST, p.permission_level, p.permission_code
            """)
    List<AdminDtos.PermissionView> findPermissions();

    @Select("""
            <script>
            SELECT count(*) FROM permission
             WHERE is_deleted = false AND permission_id IN
             <foreach item="id" collection="ids" open="(" separator="," close=")">#{id}</foreach>
            </script>
            """)
    int countLivePermissions(@Param("ids") List<Long> ids);
}
