package com.nexperia.qms.home.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.util.List;

/**
 * The home page's outstanding work, one query per stage table.
 *
 * Deliberately not a UNION ALL over the six tables: each has its own idea of
 * what "outstanding" means and its own date column, and a union would need every
 * branch cast to a common type - readable when written, unreadable when a date
 * column changes. Six small queries joined in the service are easier to correct.
 *
 * "Outstanding" is read from {@code status_code.is_final} rather than a list of
 * codes written here, so a new status is described once, in the dictionary, and
 * this stays right.
 *
 * Every query closes with the same two conditions: the complaint is not closed,
 * and the task is assigned to the given employee.
 */
@Mapper
public interface HomeMapper {

    /** The row shape every outstanding-work query returns. */
    record TodoRow(
            String taskId,
            String complaintId,
            String taskType,
            LocalDate dueDate,
            String statusText,
            String priorityCode) {
    }

    /** D2 verification tasks still open, owned by the task owner. */
    @Select("""
            SELECT t.task_id                  AS taskId,
                   t.complaint_id             AS complaintId,
                   'VERIFICATION'             AS taskType,
                   t.target_completion_date   AS dueDate,
                   sc.name_cn                 AS statusText,
                   c.priority_code            AS priorityCode
              FROM verification_task t
              JOIN complaint   c  ON c.complaint_id = t.complaint_id
              JOIN status_code sc ON sc.status_code = t.task_status
             WHERE t.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND t.task_owner_id = #{me}
               AND sc.is_final = false
            """)
    List<TodoRow> findOutstandingVerificationTasks(@Param("me") String me);

    /** D3 containment actions still open. */
    @Select("""
            SELECT ca.action_id  AS taskId,
                   ca.complaint_id AS complaintId,
                   'CONTAINMENT'  AS taskType,
                   COALESCE(ca.planned_completion_date, c.target_date) AS dueDate,
                   sc.name_cn     AS statusText,
                   c.priority_code AS priorityCode
              FROM containment_action ca
              JOIN complaint   c  ON c.complaint_id = ca.complaint_id
              JOIN status_code sc ON sc.status_code = ca.status_code
             WHERE ca.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND ca.owner_id = #{me}
               AND sc.is_final = false
            """)
    List<TodoRow> findOutstandingContainmentActions(@Param("me") String me);

    /** D5 corrective actions still open, owned by the action owner. */
    @Select("""
            SELECT cor.corrective_action_id AS taskId,
                   cor.complaint_id         AS complaintId,
                   'CORRECTIVE'             AS taskType,
                   cor.target_date          AS dueDate,
                   sc.name_cn               AS statusText,
                   c.priority_code          AS priorityCode
              FROM corrective_action cor
              JOIN complaint   c  ON c.complaint_id = cor.complaint_id
              JOIN status_code sc ON sc.status_code = cor.status_code
             WHERE cor.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND cor.owner_id = #{me}
               AND sc.is_final = false
            """)
    List<TodoRow> findOutstandingCorrectiveActions(@Param("me") String me);

    /**
     * D6: an action has been implemented and is waiting for its effectiveness
     * judgement, which the complaint's verification owner owes.
     *
     * The one place a status code is named instead of read from is_final: this is
     * the gap between "implemented" and "not yet judged", and both statuses are
     * non-final.
     */
    @Select("""
            SELECT cor.corrective_action_id AS taskId,
                   cor.complaint_id         AS complaintId,
                   'ACTION_VERIFICATION'    AS taskType,
                   cor.target_date          AS dueDate,
                   sc.name_cn               AS statusText,
                   c.priority_code          AS priorityCode
              FROM corrective_action cor
              JOIN complaint   c  ON c.complaint_id = cor.complaint_id
              JOIN status_code sc ON sc.status_code = cor.status_code
             WHERE cor.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND cor.status_code = 'CORR_DONE'
               AND c.verification_owner_id = #{me}
            """)
    List<TodoRow> findActionsAwaitingVerification(@Param("me") String me);

    /**
     * D7 prevention files still open. The table records no owner, so the work
     * falls to the complaint owner who drives the closure.
     */
    @Select("""
            SELECT p.update_id::text AS taskId,
                   p.complaint_id     AS complaintId,
                   'PREVENTION'       AS taskType,
                   c.target_date      AS dueDate,
                   sc.name_cn         AS statusText,
                   c.priority_code    AS priorityCode
              FROM prevention_file_update p
              JOIN complaint   c  ON c.complaint_id = p.complaint_id
              JOIN status_code sc ON sc.status_code = p.status_code
             WHERE p.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND c.complaint_owner_id = #{me}
               AND sc.is_final = false
            """)
    List<TodoRow> findOutstandingPreventionFiles(@Param("me") String me);

    /**
     * D4 root-cause work. The root_cause table carries no owner of its own, and
     * the stage itself is the signal that the analysis is unfinished.
     */
    @Select("""
            SELECT c.complaint_id AS taskId,
                   c.complaint_id AS complaintId,
                   'ROOT_CAUSE'   AS taskType,
                   c.target_date  AS dueDate,
                   sc.name_cn     AS statusText,
                   c.priority_code AS priorityCode
              FROM complaint   c
              JOIN status_code sc ON sc.status_code = c.status_code
             WHERE c.is_deleted = false AND c.close_date IS NULL
               AND c.current_stage = 'D4'
               AND c.complaint_owner_id = #{me}
            """)
    List<TodoRow> findRootCauseWork(@Param("me") String me);

    /**
     * D0/D1 sample and logistics entry, which the coordinator picks up: the
     * complaint has just been registered and no stage table owns this yet.
     */
    @Select("""
            SELECT c.complaint_id AS taskId,
                   c.complaint_id AS complaintId,
                   'SAMPLE_LOGISTICS' AS taskType,
                   c.target_date  AS dueDate,
                   sc.name_cn     AS statusText,
                   c.priority_code AS priorityCode
              FROM complaint   c
              JOIN status_code sc ON sc.status_code = c.status_code
             WHERE c.is_deleted = false AND c.close_date IS NULL
               AND c.current_stage IN ('D0', 'D1')
               AND c.coordinator_id = #{me}
            """)
    List<TodoRow> findSampleLogisticsWork(@Param("me") String me);

    /** Reports generated but not yet sent, owned by the report owner (编制中). */
    @Select("""
            SELECT r.report_id     AS taskId,
                   r.complaint_id  AS complaintId,
                   'REPORT'        AS taskType,
                   c.target_date   AS dueDate,
                   r.approval_status AS statusText,
                   c.priority_code AS priorityCode
              FROM report_8d r
              JOIN complaint c ON c.complaint_id = r.complaint_id
             WHERE r.is_deleted = false
               AND c.is_deleted = false AND c.close_date IS NULL
               AND r.approval_status IN ('DRAFT', 'REJECTED')
               AND c.report_owner_id = #{me}
            """)
    List<TodoRow> findDraftReports(@Param("me") String me);

    /**
     * Reports waiting for a decision, for the approver who owes it.
     *
     * This is what makes the entry "mine": the approval task names one person, so
     * the entry follows that person rather than every holder of report:approve.
     */
    @Select("""
            SELECT a.approval_id   AS taskId,
                   r.complaint_id  AS complaintId,
                   'REPORT_PENDING' AS taskType,
                   c.target_date   AS dueDate,
                   sc.name_cn      AS statusText,
                   c.priority_code AS priorityCode
              FROM approval_task a
              JOIN report_8d r ON r.report_id = a.biz_id AND r.is_deleted = false
              JOIN complaint c ON c.complaint_id = r.complaint_id
              JOIN status_code sc ON sc.status_code = a.status_code
             WHERE a.is_deleted = false AND a.biz_type = 'Report8D'
               AND c.is_deleted = false AND c.close_date IS NULL
               AND a.status_code = 'APPROVAL_PENDING'
               AND a.approver_id = #{me}
            """)
    List<TodoRow> findPendingApprovals(@Param("me") String me);

    /** Backs the "待我审批" figure: the decisions this person owes. */
    @Select("""
            SELECT count(*)
              FROM approval_task a
              JOIN report_8d r ON r.report_id = a.biz_id AND r.is_deleted = false
              JOIN complaint c ON c.complaint_id = r.complaint_id
             WHERE a.is_deleted = false AND a.biz_type = 'Report8D'
               AND c.is_deleted = false AND c.close_date IS NULL
               AND a.status_code = 'APPROVAL_PENDING'
               AND a.approver_id = #{me}
            """)
    long countPendingApprovalsFor(@Param("me") String me);
}
