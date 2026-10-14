package com.nexperia.qms.rootcause.mapper;

import com.nexperia.qms.rootcause.WhyAnalysis;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * why_analysis. content_json is jsonb, so it is written and read through explicit
 * statements with a ::jsonb cast (or ::text on the way out) rather than relying on
 * a MyBatis type handler -- fewer moving parts, and the driver can stay at runtime
 * scope.
 */
@Mapper
public interface WhyAnalysisMapper {

    @Insert("""
            INSERT INTO why_analysis
                (root_cause_id, analysis_type, content_json, is_ai_generated, version_no, created_by)
            VALUES
                (#{rootCauseId}, #{analysisType}, #{contentJson}::jsonb, false, #{versionNo},
                 #{createdBy})
            """)
    int insertJson(@Param("rootCauseId") String rootCauseId,
                   @Param("analysisType") String analysisType,
                   @Param("contentJson") String contentJson,
                   @Param("versionNo") int versionNo,
                   @Param("createdBy") String createdBy);

    /** The newest version of one tool's content, or null when none has been saved. */
    @Select("""
            SELECT wa.analysis_id AS analysisId, wa.root_cause_id AS rootCauseId,
                   wa.analysis_type AS analysisType, wa.content_json::text AS contentJson,
                   wa.version_no AS versionNo, wa.created_by AS createdBy,
                   e.name AS createdByName, wa.created_at AS createdAt
              FROM why_analysis wa
              LEFT JOIN employee e ON e.employee_id = wa.created_by
             WHERE wa.root_cause_id = #{rootCauseId} AND wa.analysis_type = #{analysisType}
               AND wa.is_deleted = false
             ORDER BY wa.version_no DESC, wa.analysis_id DESC
             LIMIT 1
            """)
    AnalysisRow findLatest(@Param("rootCauseId") String rootCauseId,
                           @Param("analysisType") String analysisType);

    /** Version history, newest first. */
    @Select("""
            SELECT wa.analysis_id AS analysisId, wa.root_cause_id AS rootCauseId,
                   wa.analysis_type AS analysisType, wa.content_json::text AS contentJson,
                   wa.version_no AS versionNo, wa.created_by AS createdBy,
                   e.name AS createdByName, wa.created_at AS createdAt
              FROM why_analysis wa
              LEFT JOIN employee e ON e.employee_id = wa.created_by
             WHERE wa.root_cause_id = #{rootCauseId} AND wa.analysis_type = #{analysisType}
               AND wa.is_deleted = false
             ORDER BY wa.version_no DESC, wa.analysis_id DESC
            """)
    List<AnalysisRow> findVersions(@Param("rootCauseId") String rootCauseId,
                                   @Param("analysisType") String analysisType);

    @Select("""
            SELECT coalesce(max(version_no), 0)
              FROM why_analysis
             WHERE root_cause_id = #{rootCauseId} AND analysis_type = #{analysisType}
               AND is_deleted = false
            """)
    int maxVersion(@Param("rootCauseId") String rootCauseId,
                   @Param("analysisType") String analysisType);

    record AnalysisRow(
            Long analysisId, String rootCauseId, String analysisType,
            String contentJson, Integer versionNo, String createdBy, String createdByName,
            OffsetDateTime createdAt) {
    }
}
