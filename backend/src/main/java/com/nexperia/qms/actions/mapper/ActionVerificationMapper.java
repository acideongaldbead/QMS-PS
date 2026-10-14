package com.nexperia.qms.actions.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.actions.ActionVerification;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface ActionVerificationMapper extends BaseMapper<ActionVerification> {

    /** The verification history of one action, newest first. */
    @Select("""
            SELECT v.verification_id AS verificationId, v.corrective_action_id AS correctiveActionId,
                   v.actual_completion_date AS actualCompletionDate,
                   v.verification_result AS verificationResult, v.is_effective AS isEffective,
                   v.verified_by AS verifiedBy, e.name AS verifiedByName, v.verified_at AS verifiedAt
              FROM action_verification v
              LEFT JOIN employee e ON e.employee_id = v.verified_by
             WHERE v.corrective_action_id = #{actionId} AND v.is_deleted = false
             ORDER BY v.verification_id DESC
            """)
    List<ActionVerificationRow> findByAction(@Param("actionId") String actionId);

    record ActionVerificationRow(
            Long verificationId, String correctiveActionId, LocalDate actualCompletionDate,
            String verificationResult, Boolean isEffective,
            String verifiedBy, String verifiedByName, OffsetDateTime verifiedAt) {
    }
}
