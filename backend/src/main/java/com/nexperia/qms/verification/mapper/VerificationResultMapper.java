package com.nexperia.qms.verification.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.verification.VerificationResult;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface VerificationResultMapper extends BaseMapper<VerificationResult> {

    @Select("""
            SELECT r.result_id AS resultId, r.task_id AS taskId, r.test_item AS testItem,
                   r.failure_type_l1_code AS failureTypeL1Code,
                   f1.name AS failureTypeL1Name,
                   r.failure_type_l2_code AS failureTypeL2Code,
                   f2.name AS failureTypeL2Name,
                   r.failure_type_l3_code AS failureTypeL3Code,
                   f3.name AS failureTypeL3Name,
                   r.result_conclusion AS resultConclusion, r.entry_mode AS entryMode,
                   r.recorded_by AS recordedBy, e.name AS recordedByName,
                   r.recorded_at AS recordedAt
              FROM verification_result r
              LEFT JOIN failure_type f1 ON f1.code = r.failure_type_l1_code
              LEFT JOIN failure_type f2 ON f2.code = r.failure_type_l2_code
              LEFT JOIN failure_type f3 ON f3.code = r.failure_type_l3_code
              LEFT JOIN employee e ON e.employee_id = r.recorded_by
             WHERE r.task_id = #{taskId} AND r.is_deleted = false
             ORDER BY r.result_id
            """)
    List<VerificationResultRow> findByTask(@Param("taskId") String taskId);

    record VerificationResultRow(
            Long resultId, String taskId, String testItem,
            String failureTypeL1Code, String failureTypeL1Name,
            String failureTypeL2Code, String failureTypeL2Name,
            String failureTypeL3Code, String failureTypeL3Name,
            String resultConclusion, String entryMode,
            String recordedBy, String recordedByName, OffsetDateTime recordedAt) {
    }
}
