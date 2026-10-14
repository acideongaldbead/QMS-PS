package com.nexperia.qms.report;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.OffsetDateTime;

/**
 * One send of a report: the communication log entry (requirement 3.9). Written
 * once when the report goes out and never edited -- the schema comment says
 * "发送后自动生成且不可修改".
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("report_distribution")
public class ReportDistribution extends BaseEntity {

    @TableId(value = "log_id", type = IdType.AUTO)
    private Long logId;

    private String reportId;

    /** Always the current Sales Quality user; never taken from the request. */
    private String senderId;

    private String recipient;
    private String ccList;
    private OffsetDateTime sentAt;

    /** The report version that was attached to this send. */
    private String attachmentVersion;

    private String channel;

    private String distributionList;
}
