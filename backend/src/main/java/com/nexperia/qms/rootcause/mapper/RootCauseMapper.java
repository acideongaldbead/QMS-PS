package com.nexperia.qms.rootcause.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.rootcause.RootCause;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface RootCauseMapper extends BaseMapper<RootCause> {

    @Select("""
            SELECT rc.root_cause_id AS rootCauseId, rc.complaint_id AS complaintId,
                   rc.root_cause_desc AS rootCauseDesc,
                   rc.root_cause_summary AS rootCauseSummary,
                   rc.risk_assessment AS riskAssessment,
                   rc.responsible_org_type AS responsibleOrgType,
                   rc.responsible_org_code AS responsibleOrgCode,
                   mo.name_cn AS responsibleOrgName,
                   rc.transferred_to_id AS transferredToId, et.name AS transferredToName,
                   rc.transferred_at AS transferredAt,
                   rc.status_code AS statusCode, sc.name_cn AS statusName,
                   rc.created_by AS createdBy, ec.name AS createdByName,
                   rc.created_at AS createdAt,
                   (SELECT count(*) FROM why_analysis wa
                     WHERE wa.root_cause_id = rc.root_cause_id AND wa.is_deleted = false
                       AND wa.analysis_type = '3x5WHY') AS whyCount,
                   (SELECT count(*) FROM why_analysis wa
                     WHERE wa.root_cause_id = rc.root_cause_id AND wa.is_deleted = false
                       AND wa.analysis_type = 'FISHBONE') AS fishboneCount
              FROM root_cause rc
              LEFT JOIN status_code sc ON sc.status_code = rc.status_code
              LEFT JOIN master_data_item mo ON mo.code = rc.responsible_org_code
              LEFT JOIN employee et ON et.employee_id = rc.transferred_to_id
              LEFT JOIN employee ec ON ec.employee_id = rc.created_by
             WHERE rc.complaint_id = #{complaintId} AND rc.is_deleted = false
             ORDER BY rc.created_at, rc.root_cause_id
            """)
    List<RootCauseRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select("""
            SELECT rc.root_cause_id AS rootCauseId, rc.complaint_id AS complaintId,
                   rc.root_cause_desc AS rootCauseDesc,
                   rc.root_cause_summary AS rootCauseSummary,
                   rc.risk_assessment AS riskAssessment,
                   rc.responsible_org_type AS responsibleOrgType,
                   rc.responsible_org_code AS responsibleOrgCode,
                   mo.name_cn AS responsibleOrgName,
                   rc.transferred_to_id AS transferredToId, et.name AS transferredToName,
                   rc.transferred_at AS transferredAt,
                   rc.status_code AS statusCode, sc.name_cn AS statusName,
                   rc.created_by AS createdBy, ec.name AS createdByName,
                   rc.created_at AS createdAt,
                   (SELECT count(*) FROM why_analysis wa
                     WHERE wa.root_cause_id = rc.root_cause_id AND wa.is_deleted = false
                       AND wa.analysis_type = '3x5WHY') AS whyCount,
                   (SELECT count(*) FROM why_analysis wa
                     WHERE wa.root_cause_id = rc.root_cause_id AND wa.is_deleted = false
                       AND wa.analysis_type = 'FISHBONE') AS fishboneCount
              FROM root_cause rc
              LEFT JOIN status_code sc ON sc.status_code = rc.status_code
              LEFT JOIN master_data_item mo ON mo.code = rc.responsible_org_code
              LEFT JOIN employee et ON et.employee_id = rc.transferred_to_id
              LEFT JOIN employee ec ON ec.employee_id = rc.created_by
             WHERE rc.root_cause_id = #{rootCauseId} AND rc.is_deleted = false
            """)
    RootCauseRow findRow(@Param("rootCauseId") String rootCauseId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record RootCauseRow(
            String rootCauseId, String complaintId,
            String rootCauseDesc, String rootCauseSummary, String riskAssessment,
            String responsibleOrgType, String responsibleOrgCode, String responsibleOrgName,
            String transferredToId, String transferredToName, OffsetDateTime transferredAt,
            String statusCode, String statusName,
            String createdBy, String createdByName, OffsetDateTime createdAt,
            Integer whyCount, Integer fishboneCount) {
    }
}
