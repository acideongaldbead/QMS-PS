package com.nexperia.qms.report;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * One row of the report's D1 cross-functional team table (Function / Name / Job
 * Title). Snapshotted when the report is generated so a staff change never
 * rewrites a report that was already sent.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("report_team_member")
public class ReportTeamMember extends BaseEntity {

    @TableId(value = "team_member_id", type = IdType.AUTO)
    private Long teamMemberId;

    private String reportId;

    private String functionName;
    private String employeeId;
    private String memberName;
    private String jobTitle;
    private Integer sortOrder;
}
