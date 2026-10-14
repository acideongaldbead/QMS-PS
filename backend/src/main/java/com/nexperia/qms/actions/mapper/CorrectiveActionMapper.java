package com.nexperia.qms.actions.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.actions.CorrectiveAction;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface CorrectiveActionMapper extends BaseMapper<CorrectiveAction> {

    String ROW_COLUMNS = """
            SELECT ca.corrective_action_id AS correctiveActionId, ca.root_cause_id AS rootCauseId,
                   ca.complaint_id AS complaintId, ca.nex_sample_number AS nexSampleNumber,
                   ca.customer_sample_id AS customerSampleId,
                   ca.planned_action_desc AS plannedActionDesc,
                   ca.owner_id AS ownerId, eo.name AS ownerName,
                   ca.target_date AS targetDate,
                   ca.status_code AS statusCode, sc.name_cn AS statusName,
                   rc.root_cause_summary AS rootCauseSummary,
                   v.verification_id AS latestVerificationId,
                   v.actual_completion_date AS actualCompletionDate,
                   v.is_effective AS isEffective,
                   v.verification_result AS verificationResult,
                   v.verified_at AS verifiedAt,
                   ev.name AS verifiedByName,
                   (SELECT count(*) FROM action_verification av
                     WHERE av.corrective_action_id = ca.corrective_action_id
                       AND av.is_deleted = false) AS verificationCount
              FROM corrective_action ca
              LEFT JOIN employee eo ON eo.employee_id = ca.owner_id
              LEFT JOIN status_code sc ON sc.status_code = ca.status_code
              LEFT JOIN root_cause rc ON rc.root_cause_id = ca.root_cause_id
              LEFT JOIN LATERAL (
                    SELECT av.verification_id, av.actual_completion_date, av.is_effective,
                           av.verification_result, av.verified_at, av.verified_by
                      FROM action_verification av
                     WHERE av.corrective_action_id = ca.corrective_action_id
                       AND av.is_deleted = false
                     ORDER BY av.verification_id DESC
                     LIMIT 1
              ) v ON true
              LEFT JOIN employee ev ON ev.employee_id = v.verified_by
            """;

    @Select(ROW_COLUMNS + " WHERE ca.complaint_id = #{complaintId} AND ca.is_deleted = false"
            + " ORDER BY ca.created_at, ca.corrective_action_id")
    List<CorrectiveActionRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select(ROW_COLUMNS + " WHERE ca.corrective_action_id = #{actionId} AND ca.is_deleted = false")
    CorrectiveActionRow findRow(@Param("actionId") String actionId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record CorrectiveActionRow(
            String correctiveActionId, String rootCauseId, String complaintId,
            String nexSampleNumber, String customerSampleId, String plannedActionDesc,
            String ownerId, String ownerName, LocalDate targetDate,
            String statusCode, String statusName, String rootCauseSummary,
            Long latestVerificationId, LocalDate actualCompletionDate, Boolean isEffective,
            String verificationResult, OffsetDateTime verifiedAt, String verifiedByName,
            Integer verificationCount) {
    }
}
