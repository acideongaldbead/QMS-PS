package com.nexperia.qms.verification.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.verification.VerificationTask;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface VerificationTaskMapper extends BaseMapper<VerificationTask> {

    @Select("""
            SELECT t.task_id AS taskId, t.complaint_id AS complaintId,
                   t.sample_id AS sampleId, s.customer_sample_id AS sampleCustomerSampleId,
                   t.task_owner_id AS taskOwnerId, e.name AS taskOwnerName,
                   t.planned_start_date AS plannedStartDate,
                   t.target_completion_date AS targetCompletionDate,
                   t.creation_mode AS creationMode,
                   t.task_status AS taskStatus, sc.name_cn AS taskStatusName,
                   t.completed_at AS completedAt,
                   (SELECT count(*) FROM verification_result r
                     WHERE r.task_id = t.task_id AND r.is_deleted = false) AS resultCount
              FROM verification_task t
              LEFT JOIN employee e ON e.employee_id = t.task_owner_id
              LEFT JOIN sample s ON s.sample_id = t.sample_id
              LEFT JOIN status_code sc ON sc.status_code = t.task_status
             WHERE t.complaint_id = #{complaintId} AND t.is_deleted = false
             ORDER BY t.created_at, t.task_id
            """)
    List<VerificationTaskRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select("""
            SELECT t.task_id AS taskId, t.complaint_id AS complaintId,
                   t.sample_id AS sampleId, s.customer_sample_id AS sampleCustomerSampleId,
                   t.task_owner_id AS taskOwnerId, e.name AS taskOwnerName,
                   t.planned_start_date AS plannedStartDate,
                   t.target_completion_date AS targetCompletionDate,
                   t.creation_mode AS creationMode,
                   t.task_status AS taskStatus, sc.name_cn AS taskStatusName,
                   t.completed_at AS completedAt,
                   (SELECT count(*) FROM verification_result r
                     WHERE r.task_id = t.task_id AND r.is_deleted = false) AS resultCount
              FROM verification_task t
              LEFT JOIN employee e ON e.employee_id = t.task_owner_id
              LEFT JOIN sample s ON s.sample_id = t.sample_id
              LEFT JOIN status_code sc ON sc.status_code = t.task_status
             WHERE t.task_id = #{taskId} AND t.is_deleted = false
            """)
    VerificationTaskRow findRow(@Param("taskId") String taskId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record VerificationTaskRow(
            String taskId, String complaintId,
            String sampleId, String sampleCustomerSampleId,
            String taskOwnerId, String taskOwnerName,
            LocalDate plannedStartDate, LocalDate targetCompletionDate,
            String creationMode, String taskStatus, String taskStatusName,
            OffsetDateTime completedAt, Integer resultCount) {
    }
}
