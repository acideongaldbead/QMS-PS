package com.nexperia.qms.containment.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.containment.ContainmentAction;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface ContainmentActionMapper extends BaseMapper<ContainmentAction> {

    @Select("""
            SELECT a.action_id AS actionId, a.complaint_id AS complaintId,
                   a.nex_sample_number AS nexSampleNumber,
                   a.customer_sample_number AS customerSampleNumber,
                   a.planned_action AS plannedAction,
                   a.owner_id AS ownerId, e.name AS ownerName,
                   a.planned_completion_date AS plannedCompletionDate,
                   a.completed_date AS completedDate,
                   a.status_code AS statusCode, sc.name_cn AS statusName,
                   a.result AS result, a.created_by AS createdBy,
                   eo.name AS createdByName, a.created_at AS createdAt
              FROM containment_action a
              LEFT JOIN employee e ON e.employee_id = a.owner_id
              LEFT JOIN employee eo ON eo.employee_id = a.created_by
              LEFT JOIN status_code sc ON sc.status_code = a.status_code
             WHERE a.complaint_id = #{complaintId} AND a.is_deleted = false
             ORDER BY a.created_at, a.action_id
            """)
    List<ContainmentRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select("""
            SELECT a.action_id AS actionId, a.complaint_id AS complaintId,
                   a.nex_sample_number AS nexSampleNumber,
                   a.customer_sample_number AS customerSampleNumber,
                   a.planned_action AS plannedAction,
                   a.owner_id AS ownerId, e.name AS ownerName,
                   a.planned_completion_date AS plannedCompletionDate,
                   a.completed_date AS completedDate,
                   a.status_code AS statusCode, sc.name_cn AS statusName,
                   a.result AS result, a.created_by AS createdBy,
                   eo.name AS createdByName, a.created_at AS createdAt
              FROM containment_action a
              LEFT JOIN employee e ON e.employee_id = a.owner_id
              LEFT JOIN employee eo ON eo.employee_id = a.created_by
              LEFT JOIN status_code sc ON sc.status_code = a.status_code
             WHERE a.action_id = #{actionId} AND a.is_deleted = false
            """)
    ContainmentRow findRow(@Param("actionId") String actionId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record ContainmentRow(
            String actionId, String complaintId,
            String nexSampleNumber, String customerSampleNumber,
            String plannedAction, String ownerId, String ownerName,
            LocalDate plannedCompletionDate, LocalDate completedDate,
            String statusCode, String statusName,
            String result, String createdBy, String createdByName,
            OffsetDateTime createdAt) {
    }
}
