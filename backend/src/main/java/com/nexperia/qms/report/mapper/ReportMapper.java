package com.nexperia.qms.report.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.report.Report8D;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Collection;
import java.util.List;

@Mapper
public interface ReportMapper extends BaseMapper<Report8D> {

    @Select("""
            SELECT * FROM report_8d
             WHERE complaint_id = #{complaintId} AND is_deleted = false
             ORDER BY created_at DESC, report_id DESC
            """)
    List<Report8D> findByComplaint(@Param("complaintId") String complaintId);

    /** Corrective actions that are not yet verified: the D8 report must not close over them. */
    @Select("""
            SELECT count(*) FROM corrective_action
             WHERE complaint_id = #{complaintId} AND is_deleted = false
               AND status_code <> 'CORR_VERIFIED'
            """)
    int countUnverifiedActions(@Param("complaintId") String complaintId);

    /** Employee display data for the report's D1 team snapshot. */
    @Select("""
            <script>
            SELECT employee_id AS employeeId, name AS name, job_title AS jobTitle
              FROM employee
             WHERE is_deleted = false
               AND employee_id IN <foreach item="i" collection="ids" open="(" separator="," close=")">#{i}</foreach>
            </script>
            """)
    List<EmployeeRow> findEmployeeRows(@Param("ids") Collection<String> ids);

    record EmployeeRow(String employeeId, String name, String jobTitle) {
    }
}
