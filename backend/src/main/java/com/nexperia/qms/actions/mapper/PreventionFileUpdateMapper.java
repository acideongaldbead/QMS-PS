package com.nexperia.qms.actions.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.actions.PreventionFileUpdate;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface PreventionFileUpdateMapper extends BaseMapper<PreventionFileUpdate> {

    @Select("""
            SELECT p.update_id AS updateId, p.complaint_id AS complaintId,
                   p.nex_sample_number AS nexSampleNumber,
                   p.customer_sample_id AS customerSampleId,
                   p.file_type_code AS fileTypeCode, mt.name_cn AS fileTypeName,
                   p.control_program AS controlProgram,
                   p.reference_number AS referenceNumber,
                   p.status_code AS statusCode, sc.name_cn AS statusName,
                   p.created_by AS createdBy, e.name AS createdByName,
                   p.created_at AS createdAt
              FROM prevention_file_update p
              LEFT JOIN master_data_item mt ON mt.code = p.file_type_code
              LEFT JOIN status_code sc ON sc.status_code = p.status_code
              LEFT JOIN employee e ON e.employee_id = p.created_by
             WHERE p.complaint_id = #{complaintId} AND p.is_deleted = false
             ORDER BY p.created_at, p.update_id
            """)
    List<PreventionRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select("""
            SELECT p.update_id AS updateId, p.complaint_id AS complaintId,
                   p.nex_sample_number AS nexSampleNumber,
                   p.customer_sample_id AS customerSampleId,
                   p.file_type_code AS fileTypeCode, mt.name_cn AS fileTypeName,
                   p.control_program AS controlProgram,
                   p.reference_number AS referenceNumber,
                   p.status_code AS statusCode, sc.name_cn AS statusName,
                   p.created_by AS createdBy, e.name AS createdByName,
                   p.created_at AS createdAt
              FROM prevention_file_update p
              LEFT JOIN master_data_item mt ON mt.code = p.file_type_code
              LEFT JOIN status_code sc ON sc.status_code = p.status_code
              LEFT JOIN employee e ON e.employee_id = p.created_by
             WHERE p.update_id = #{updateId} AND p.is_deleted = false
            """)
    PreventionRow findRow(@Param("updateId") Long updateId);

    /** Files still outstanding for a complaint; D8 cannot start while any remain. */
    @Select("""
            SELECT count(*) FROM prevention_file_update p
              JOIN status_code sc ON sc.status_code = p.status_code
             WHERE p.complaint_id = #{complaintId} AND p.is_deleted = false
               AND coalesce(sc.is_final, false) = false
            """)
    int countOutstanding(@Param("complaintId") String complaintId);

    record PreventionRow(
            Long updateId, String complaintId,
            String nexSampleNumber, String customerSampleId,
            String fileTypeCode, String fileTypeName,
            String controlProgram, String referenceNumber,
            String statusCode, String statusName,
            String createdBy, String createdByName, OffsetDateTime createdAt) {
    }
}
