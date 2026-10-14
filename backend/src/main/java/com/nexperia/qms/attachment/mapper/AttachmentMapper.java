package com.nexperia.qms.attachment.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.attachment.Attachment;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface AttachmentMapper extends BaseMapper<Attachment> {

    /**
     * Confirms the record an attachment points at actually exists. There is no
     * foreign key to lean on, so this stands in for one.
     *
     * Every branch returns a single column named id so the union is well formed;
     * an unknown biz_type matches nothing and yields 0.
     */
    @Select("""
            <script>
            SELECT count(*) FROM (
              <choose>
                <when test="bizType == 'Complaint'">
                  SELECT complaint_id AS id FROM complaint WHERE complaint_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'Sample'">
                  SELECT sample_id AS id FROM sample WHERE sample_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'Shipment'">
                  SELECT shipment_id AS id FROM shipment WHERE shipment_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'VerificationTask'">
                  SELECT task_id AS id FROM verification_task WHERE task_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'ContainmentAction'">
                  SELECT action_id AS id FROM containment_action WHERE action_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'RootCause'">
                  SELECT root_cause_id AS id FROM root_cause WHERE root_cause_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'CorrectiveAction'">
                  SELECT corrective_action_id AS id FROM corrective_action WHERE corrective_action_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'PreventionFileUpdate'">
                  SELECT update_id AS id FROM prevention_file_update WHERE update_id = #{bizId} AND is_deleted = false
                </when>
                <when test="bizType == 'Report8D'">
                  SELECT report_id AS id FROM report_8d WHERE report_id = #{bizId} AND is_deleted = false
                </when>
                <!--
                  Every other parent keys on a varchar business number, so the raw
                  comparison works. This one is a bigint identity: `article_id = #{bizId}`
                  would fail with "operator does not exist: bigint = character varying",
                  and casting the parameter with CAST(... AS bigint) would turn a
                  malformed id into a 500 instead of a clean "not found". Comparing as
                  text is safe for any input; the table is a dozen rows, so the index
                  does not matter.
                -->
                <when test="bizType == 'KnowledgeArticle'">
                  SELECT article_id AS id FROM knowledge_article WHERE article_id::text = #{bizId} AND is_deleted = false
                </when>
                <otherwise>
                  SELECT NULL AS id WHERE false
                </otherwise>
              </choose>
            ) t
            </script>
            """)
    int countParent(@Param("bizType") String bizType, @Param("bizId") String bizId);

    /**
     * The attachment list with the uploader's name resolved, so the attachment
     * centre does not show raw employee ids.
     */
    @Select("""
            SELECT a.attachment_id AS attachmentId, a.biz_type AS bizType, a.biz_id AS bizId,
                   a.file_name AS fileName, a.file_size AS fileSize, a.file_type AS fileType,
                   a.uploaded_by AS uploadedBy, e.name AS uploadedByName,
                   a.uploaded_at AS uploadedAt
              FROM attachment a
              LEFT JOIN employee e ON e.employee_id = a.uploaded_by
             WHERE a.biz_type = #{bizType} AND a.biz_id = #{bizId} AND a.is_deleted = false
             ORDER BY a.uploaded_at DESC, a.attachment_id DESC
            """)
    List<AttachmentRow> findByBiz(@Param("bizType") String bizType, @Param("bizId") String bizId);

    /**
     * Every column the client needs, resolved. Component names must all have a
     * matching column: MyBatis builds records through the constructor.
     */
    record AttachmentRow(Long attachmentId, String bizType, String bizId, String fileName,
                         Long fileSize, String fileType, String uploadedBy,
                         String uploadedByName, OffsetDateTime uploadedAt) {
    }
}
