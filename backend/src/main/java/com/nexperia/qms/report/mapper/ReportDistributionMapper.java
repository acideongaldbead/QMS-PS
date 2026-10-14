package com.nexperia.qms.report.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.report.ReportDistribution;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface ReportDistributionMapper extends BaseMapper<ReportDistribution> {

    String ROW_COLUMNS = """
            SELECT d.log_id AS logId, d.report_id AS reportId, d.sender_id AS senderId,
                   e.name AS senderName, d.recipient, d.cc_list AS ccList, d.sent_at AS sentAt,
                   d.attachment_version AS attachmentVersion, d.channel,
                   d.distribution_list AS distributionList
              FROM report_distribution d
              LEFT JOIN employee e ON e.employee_id = d.sender_id
            """;

    @Select(ROW_COLUMNS + " WHERE d.report_id = #{reportId} AND d.is_deleted = false"
            + " ORDER BY d.sent_at DESC, d.log_id DESC")
    List<DistributionRow> findByReport(@Param("reportId") String reportId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record DistributionRow(
            Long logId, String reportId, String senderId, String senderName,
            String recipient, String ccList, OffsetDateTime sentAt,
            String attachmentVersion, String channel, String distributionList) {
    }
}
