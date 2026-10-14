package com.nexperia.qms.complaint.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.dto.ComplaintLabels;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.util.List;

@Mapper
public interface ComplaintMapper extends BaseMapper<Complaint> {

    /**
     * Resolves every display name the detail page shows, in one round trip, by
     * following the 1:1 blocks out to their master data. The frontend would
     * otherwise need a handful of lookups just to render the header.
     */
    @Select("""
            SELECT cu.customer_name       AS customerName,
                   ct.contact_name        AS contactName,
                   ct.email               AS contactEmail,
                   st.ship_to_name        AS shipToName,
                   pm.description         AS productDescription,
                   eo.name                AS ownerName,
                   ec.name                AS coordinatorName,
                   ev.name                AS verificationOwnerName,
                   er.name                AS reportOwnerName,
                   ecr.name               AS createdByName,
                   mt.name_cn             AS complaintTypeName,
                   mp.name_cn             AS priorityName,
                   mf.name_cn             AS failureLocationName,
                   ms.name_cn             AS subSegmentName,
                   md.name_cn             AS customerFailureModeName,
                   sc.name_cn             AS statusName
              FROM complaint c
              LEFT JOIN quality_partner    qp ON qp.complaint_id = c.complaint_id AND qp.is_deleted = false
              LEFT JOIN customer           cu ON cu.customer_code = qp.quality_partner_code
              LEFT JOIN contact_person     ct ON ct.contact_id = qp.contact_person_id
              LEFT JOIN ship_to_sold_to    st ON st.ship_to_code = qp.ship_to_sold_to_code
              LEFT JOIN master_data_item   ms ON ms.code = qp.sub_segment_code
              LEFT JOIN product_info       pi ON pi.complaint_id = c.complaint_id AND pi.is_deleted = false
              LEFT JOIN product_master     pm ON pm.material_code = pi.material_code
              LEFT JOIN employee           eo ON eo.employee_id = c.complaint_owner_id
              LEFT JOIN employee           ec ON ec.employee_id = c.coordinator_id
              LEFT JOIN employee           ev ON ev.employee_id = c.verification_owner_id
              LEFT JOIN employee           er ON er.employee_id = c.report_owner_id
              LEFT JOIN employee           ecr ON ecr.employee_id = c.created_by
              LEFT JOIN master_data_item   mt ON mt.code = c.complaint_type_code
              LEFT JOIN master_data_item   mp ON mp.code = c.priority_code
              LEFT JOIN master_data_item   mf ON mf.code = c.failure_location_code
              LEFT JOIN failure_description fd ON fd.complaint_id = c.complaint_id AND fd.is_deleted = false
              LEFT JOIN master_data_item   md ON md.code = fd.customer_failure_mode_code
              LEFT JOIN status_code        sc ON sc.status_code = c.status_code
             WHERE c.complaint_id = #{complaintId} AND c.is_deleted = false
            """)
    ComplaintLabels findLabels(@Param("complaintId") String complaintId);

    /**
     * The complaint ledger query (requirement 3.1.1): paged, filtered, sorted.
     *
     * <p>Sorting is a whitelist of {@code <choose>} branches rather than a column
     * name interpolated into the statement. The default branch reproduces the
     * prototype's order - still-open first, then the most overdue, then the newest
     * number - and is also what an unknown sort key falls back to.
     *
     * <p>{@code desc} is only consulted on the whitelisted branches, so a caller
     * cannot reach the ORDER BY through anything but the keys listed below.
     */
    @Select("""
            <script>
            SELECT c.complaint_id          AS complaintId,
                   c.status_code           AS statusCode,
                   sc.name_cn              AS statusName,
                   c.current_stage         AS currentStage,
                   c.priority_code         AS priorityCode,
                   mp.name_cn              AS priorityName,
                   cu.customer_name        AS customerName,
                   pi.material_code        AS productCode,
                   mpt.name_cn             AS productTypeName,
                   c.start_date            AS startDate,
                   c.target_date           AS targetDate,
                   c.close_date            AS closeDate,
                   c.close_reason_code     AS closeReasonCode,
                   (CASE WHEN c.close_date IS NULL
                         THEN (CURRENT_DATE - c.created_at::date)
                         ELSE (c.close_date - c.created_at::date) END) AS processingDays,
                   c.complaint_owner_id    AS ownerId,
                   eo.name                 AS ownerName,
                   c.customer_reference_id AS customerReferenceId,
                   (CASE WHEN c.close_date IS NULL AND c.target_date &lt; CURRENT_DATE
                         THEN (CURRENT_DATE - c.target_date) ELSE 0 END) AS overdueDays,
                   complaint_related(c.complaint_id, #{me}) AS mine
              FROM complaint c
              LEFT JOIN quality_partner  qp ON qp.complaint_id = c.complaint_id AND qp.is_deleted = false
              LEFT JOIN customer         cu ON cu.customer_code = qp.quality_partner_code
              LEFT JOIN product_info     pi ON pi.complaint_id = c.complaint_id AND pi.is_deleted = false
              LEFT JOIN product_master   pm ON pm.material_code = pi.material_code
              LEFT JOIN master_data_item mpt ON mpt.code = pi.product_type_code
              LEFT JOIN employee         eo ON eo.employee_id = c.complaint_owner_id
              LEFT JOIN status_code      sc ON sc.status_code = c.status_code
              LEFT JOIN master_data_item mp ON mp.code = c.priority_code
             WHERE c.is_deleted = false
             <if test="mineOnly">
               AND complaint_related(c.complaint_id, #{me})
             </if>
             <if test="q != null and q != ''">
               AND (c.complaint_id ILIKE '%' || #{q} || '%'
                 OR c.customer_reference_id ILIKE '%' || #{q} || '%'
                 OR cu.customer_name ILIKE '%' || #{q} || '%'
                 OR pi.material_code ILIKE '%' || #{q} || '%')
             </if>
             <if test="status != null and status != ''">AND c.status_code = #{status}</if>
             <if test="priority != null and priority != ''">AND c.priority_code = #{priority}</if>
             <if test="customer != null and customer != ''">AND qp.quality_partner_code = #{customer}</if>
             <if test="complaintType != null and complaintType != ''">AND c.complaint_type_code = #{complaintType}</if>
             <if test="owner != null and owner != ''">AND c.complaint_owner_id = #{owner}</if>
             <if test="product != null and product != ''">AND pi.material_code ILIKE '%' || #{product} || '%'</if>
             <if test="startFrom != null">AND c.start_date &gt;= #{startFrom}</if>
             <if test="startTo != null">AND c.start_date &lt;= #{startTo}</if>
             <if test="targetFrom != null">AND c.target_date &gt;= #{targetFrom}</if>
             <if test="targetTo != null">AND c.target_date &lt;= #{targetTo}</if>
             <if test="overdueOnly">AND c.close_date IS NULL AND c.target_date &lt; CURRENT_DATE</if>
             <if test="openOnly">AND c.close_date IS NULL</if>
             <if test="validOnly">AND c.is_valid = true</if>
             <if test="ids != null and ids.size() > 0">
               AND c.complaint_id IN
               <foreach item="x" collection="ids" open="(" separator="," close=")">#{x}</foreach>
             </if>
             ORDER BY
             <choose>
               <when test="sort == 'id'">c.complaint_id <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'status'">c.status_code <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'stage'">c.current_stage <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'priority'">c.priority_code <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'customer'">cu.customer_name <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'product'">mpt.name_cn <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'startDate'">c.start_date <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'targetDate'">c.target_date <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'closeDate'">c.close_date <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'days'">(CASE WHEN c.close_date IS NULL
                         THEN (CURRENT_DATE - c.created_at::date)
                         ELSE (c.close_date - c.created_at::date) END) <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'owner'">eo.name <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <when test="sort == 'customerRefId'">c.customer_reference_id <if test="desc">DESC</if><if test="!desc">ASC</if>, c.complaint_id DESC</when>
               <otherwise>
                 (c.close_date IS NULL) DESC,
                 (CASE WHEN c.close_date IS NULL AND c.target_date &lt; CURRENT_DATE
                       THEN (CURRENT_DATE - c.target_date) ELSE 0 END) DESC,
                 c.complaint_id DESC
               </otherwise>
             </choose>
            </script>
            """)
    List<ComplaintResponses.LedgerRow> findLedger(
            IPage<ComplaintResponses.LedgerRow> page,
            @Param("me") String me,
            @Param("mineOnly") boolean mineOnly,
            @Param("q") String q,
            @Param("status") String status,
            @Param("priority") String priority,
            @Param("customer") String customer,
            @Param("complaintType") String complaintType,
            @Param("owner") String owner,
            @Param("product") String product,
            @Param("startFrom") LocalDate startFrom,
            @Param("startTo") LocalDate startTo,
            @Param("targetFrom") LocalDate targetFrom,
            @Param("targetTo") LocalDate targetTo,
            @Param("overdueOnly") boolean overdueOnly,
            @Param("openOnly") boolean openOnly,
            @Param("validOnly") boolean validOnly,
            @Param("sort") String sort,
            @Param("desc") boolean desc,
            @Param("ids") List<String> ids);

    /** Backs the two ledger tab counters; no filters, so no joins. */
    @Select("""
            <script>
            SELECT count(*) FROM complaint c
             WHERE c.is_deleted = false
             <if test="mineOnly">
               AND complaint_related(c.complaint_id, #{me})
             </if>
            </script>
            """)
    long countLedger(@Param("me") String me, @Param("mineOnly") boolean mineOnly);
}
