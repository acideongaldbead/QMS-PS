package com.nexperia.qms.rootcause;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * The 3x5Why or fishbone content of one root cause (requirement 3.5).
 *
 * Rows are append-only per version: saving again writes a new row with
 * version_no + 1 rather than overwriting, which is what gives the screen version
 * history for free. {@code contentJson} is handled as text and cast to jsonb in
 * the mapper, so no MyBatis type handler is needed.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("why_analysis")
public class WhyAnalysis extends BaseEntity {

    @TableId(value = "analysis_id", type = IdType.AUTO)
    private Long analysisId;

    private String rootCauseId;

    /** 3x5WHY or FISHBONE. */
    private String analysisType;

    /** Serialised structured content; stored as jsonb. */
    private String contentJson;

    /** Phase 1 never generates this; kept false so phase 2 needs no migration (Q-03). */
    private Boolean isAiGenerated;

    private String aiQualityFeedback;

    private Integer versionNo;
}
