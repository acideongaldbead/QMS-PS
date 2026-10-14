package com.nexperia.qms.complaintlog.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * The two sources behind the complaint's "沟通与流程日志" tab.
 *
 * The audit trail carries the process history: every stage service records its
 * actions with the <b>complaint id</b> as biz_id (even when biz_type is
 * VerificationTask or CorrectiveAction), so one lookup by biz_id returns the whole
 * trail of a complaint regardless of which module wrote the row.
 */
@Mapper
public interface ComplaintLogMapper {

    /** Component order must match the select list: MyBatis maps by position. */
    record AuditRow(
            OffsetDateTime at,
            String actorName,
            String bizType,
            String actionType,
            String beforeValue,
            String afterValue) {
    }

    record CommunicationRow(
            OffsetDateTime at,
            String actorName,
            String recipient,
            String ccList,
            String channel,
            String attachmentVersion) {
    }

    @Select("""
            SELECT a.created_at   AS at,
                   e.name         AS actorName,
                   a.biz_type     AS bizType,
                   a.action_type  AS actionType,
                   a.before_value AS beforeValue,
                   a.after_value  AS afterValue
              FROM audit_log a
              LEFT JOIN employee e ON e.employee_id = a.operator_id
             WHERE a.biz_id = #{complaintId} AND a.is_deleted = false
             ORDER BY a.created_at DESC, a.log_id DESC
            """)
    List<AuditRow> findAuditRows(@Param("complaintId") String complaintId);

    /** Communication log: the mails the report was actually sent with. */
    @Select("""
            SELECT COALESCE(d.sent_at, d.created_at) AS at,
                   e.name            AS actorName,
                   d.recipient       AS recipient,
                   d.cc_list         AS ccList,
                   d.channel         AS channel,
                   d.attachment_version AS attachmentVersion
              FROM report_distribution d
              JOIN report_8d r ON r.report_id = d.report_id
              LEFT JOIN employee e ON e.employee_id = d.sender_id
             WHERE r.complaint_id = #{complaintId}
               AND d.is_deleted = false AND r.is_deleted = false
             ORDER BY d.sent_at DESC NULLS LAST, d.log_id DESC
            """)
    List<CommunicationRow> findCommunications(@Param("complaintId") String complaintId);

    @Select("""
            SELECT count(*) FROM complaint
             WHERE complaint_id = #{complaintId} AND is_deleted = false
            """)
    int countComplaint(@Param("complaintId") String complaintId);
}
