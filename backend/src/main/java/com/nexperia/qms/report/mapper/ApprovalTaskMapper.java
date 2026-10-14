package com.nexperia.qms.report.mapper;

import com.nexperia.qms.report.dto.ReportDtos;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * The report's view of the shared {@code approval_task} table.
 *
 * It lives in the report module because that is the only flow wired to it so far;
 * the table itself is generic (biz_type/biz_id) and a second flow can add its own
 * mapper without touching this one.
 *
 * The status codes are the APPROVAL_* entries seeded into status_code, which is
 * why the insert and the complete statement name them literally.
 */
@Mapper
public interface ApprovalTaskMapper {

    /** Component order must match the select list: MyBatis maps by position. */
    record ApprovalRow(
            String approvalId,
            String approverId,
            String approverName,
            String statusCode,
            String comment,
            OffsetDateTime pushedAt,
            OffsetDateTime completedAt) {
    }

    /** The newest task for a report, which is the one whose decision counts. */
    @Select("""
            SELECT a.approval_id      AS approvalId,
                   a.approver_id      AS approverId,
                   e.name             AS approverName,
                   a.status_code      AS statusCode,
                   a.approval_comment AS comment,
                   a.pushed_at        AS pushedAt,
                   a.completed_at     AS completedAt
              FROM approval_task a
              LEFT JOIN employee e ON e.employee_id = a.approver_id
             WHERE a.biz_type = 'Report8D' AND a.biz_id = #{reportId} AND a.is_deleted = false
             ORDER BY a.created_at DESC, a.approval_id DESC
             LIMIT 1
            """)
    ApprovalRow findLatestByReport(@Param("reportId") String reportId);

    @Insert("""
            INSERT INTO approval_task
                (approval_id, biz_type, biz_id, approver_id, status_code, pushed_at, created_by, updated_by)
            VALUES
                (#{approvalId}, 'Report8D', #{reportId}, #{approverId}, 'APPROVAL_PENDING', now(), #{by}, #{by})
            """)
    int insert(@Param("approvalId") String approvalId,
               @Param("reportId") String reportId,
               @Param("approverId") String approverId,
               @Param("by") String by);

    @Update("""
            UPDATE approval_task
               SET status_code = #{statusCode},
                   approval_comment = #{comment},
                   completed_at = now(),
                   updated_at = now(),
                   updated_by = #{by}
             WHERE approval_id = #{approvalId}
            """)
    int complete(@Param("approvalId") String approvalId,
                 @Param("statusCode") String statusCode,
                 @Param("comment") String comment,
                 @Param("by") String by);

    /** Employees holding report:approve, newest role assignment irrelevant. */
    @Select("""
            SELECT DISTINCT e.employee_id AS employeeId, e.name AS name
              FROM employee e
              JOIN user_role       ur ON ur.employee_id = e.employee_id
              JOIN role_permission rp ON rp.role_id = ur.role_id
              JOIN permission      p  ON p.permission_id = rp.permission_id
             WHERE p.permission_code = 'report:approve'
               AND e.is_active = true AND e.is_deleted = false
             ORDER BY e.name
            """)
    List<ReportDtos.Approver> findApprovers();
}
