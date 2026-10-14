package com.nexperia.qms.complaint.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.complaint.Sample;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.math.BigDecimal;
import java.util.List;

@Mapper
public interface SampleMapper extends BaseMapper<Sample> {

    /**
     * The complaint's samples with the failure type name resolved, which is what
     * the logistics screen shows on both sides of the transfer list.
     */
    @Select("""
            SELECT s.sample_id AS sampleId, s.customer_sample_id AS customerSampleId,
                   s.champ_id AS champId, s.description AS description,
                   s.sample_quantity AS quantity, s.uom AS uom,
                   s.reject_confirmed AS rejectConfirmed, f3.name AS failureTypeName
              FROM sample s
              LEFT JOIN failure_type f3 ON f3.code = s.failure_type_l3_code
             WHERE s.complaint_id = #{complaintId} AND s.is_deleted = false
             ORDER BY s.sample_id
            """)
    List<SampleRow> findRowsByComplaint(@Param("complaintId") String complaintId);

    record SampleRow(
            String sampleId, String customerSampleId, String champId, String description,
            BigDecimal quantity, String uom, Boolean rejectConfirmed, String failureTypeName) {
    }

    /**
     * Confirms a sample belongs to the complaint in the URL. A shipment's sample
     * list reaching across complaints would be a data-integrity hole, and no
     * foreign key can prevent it.
     */
    @Select("""
            SELECT count(*) FROM sample
             WHERE sample_id = #{sampleId} AND complaint_id = #{complaintId} AND is_deleted = false
            """)
    int countSampleOfComplaint(@Param("sampleId") String sampleId,
                               @Param("complaintId") String complaintId);
}
