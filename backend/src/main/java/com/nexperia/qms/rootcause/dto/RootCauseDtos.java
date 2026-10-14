package com.nexperia.qms.rootcause.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;

public final class RootCauseDtos {

    private RootCauseDtos() {
    }

    /** Create or update a root-cause entry (requirement 3.5). */
    public record RootCauseRequest(
            @NotBlank(message = "根因描述不能为空") String rootCauseDesc,
            @Size(max = 500) String rootCauseSummary,
            String riskAssessment,
            /** INTERNAL or EXTERNAL; the flowchart's "root cause inside Nexperia?" branch. */
            @Pattern(regexp = "INTERNAL|EXTERNAL", message = "根因归属只能是内部或外部") String responsibleOrgType,
            String responsibleOrgCode,
            String statusCode) {
    }

    /** Hands a root cause to another organisation (PS-047). */
    public record TransferRequest(
            @NotBlank(message = "转交对象不能为空") String transferredToId,
            String responsibleOrgType,
            String responsibleOrgCode,
            String note) {
    }

    public record RootCauseView(
            String rootCauseId,
            String complaintId,
            String rootCauseDesc,
            String rootCauseSummary,
            String riskAssessment,
            String responsibleOrgType,
            String responsibleOrgCode,
            String responsibleOrgName,
            String transferredToId,
            String transferredToName,
            OffsetDateTime transferredAt,
            String statusCode,
            String statusName,
            String createdBy,
            String createdByName,
            OffsetDateTime createdAt,
            int whyVersionCount,
            int fishboneVersionCount) {
    }

    /**
     * A saved snapshot of one tool. contentJson is the serialised structured
     * content; the frontend decides its shape per analysisType.
     */
    public record AnalysisRequest(
            @NotBlank(message = "分析类型不能为空")
            /** Case-insensitive: the canonical value is 3x5WHY, but clients may send any casing. */
            @Pattern(regexp = "(?i)3x5why|fishbone", message = "分析类型只能是 3x5WHY 或 FISHBONE")
            String analysisType,
            @NotBlank(message = "分析内容不能为空") String contentJson) {
    }

    public record AnalysisView(
            Long analysisId,
            String rootCauseId,
            String analysisType,
            String contentJson,
            Integer versionNo,
            String createdBy,
            String createdByName,
            OffsetDateTime createdAt) {
    }

    /**
     * A root cause plus the newest version of each tool, so the screen can render
     * the editors without a second round trip.
     */
    public record RootCauseDetail(
            RootCauseView rootCause,
            AnalysisView whyAnalysis,
            AnalysisView fishbone) {
    }
}
