package com.nexperia.qms.logistics.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.logistics.ShipmentSample;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.math.BigDecimal;
import java.util.List;

@Mapper
public interface ShipmentSampleMapper extends BaseMapper<ShipmentSample> {

    /**
     * Samples in a shipment, with the sample's own failure type resolved. The
     * per-batch attributes come from the link row; the sample identity and its
     * failure classification come from the sample.
     */
    @Select("""
            SELECT ss.shipment_sample_id AS shipmentSampleId, ss.shipment_id AS shipmentId,
                   ss.sample_id AS sampleId, s.customer_sample_id AS sampleCustomerSampleId,
                   COALESCE(ss.customer_sample_id, s.customer_sample_id) AS customerSampleId,
                   ss.description AS description, ss.date_code AS dateCode, ss.db_id AS dbId,
                   ss.qty AS qty, ss.uom AS uom, ss.assembly_center AS assemblyCenter,
                   ss.test_center AS testCenter, ss.num_of_dies AS numOfDies,
                   f3.name AS failureTypeName
              FROM shipment_sample ss
              JOIN sample s ON s.sample_id = ss.sample_id
              LEFT JOIN failure_type f3 ON f3.code = s.failure_type_l3_code
             WHERE ss.shipment_id = #{shipmentId} AND ss.is_deleted = false
             ORDER BY ss.shipment_sample_id
            """)
    List<ShipmentSampleRow> findByShipment(@Param("shipmentId") String shipmentId);

    @Select("""
            SELECT count(*) FROM shipment_sample
             WHERE shipment_id = #{shipmentId} AND sample_id = #{sampleId} AND is_deleted = false
            """)
    int countLink(@Param("shipmentId") String shipmentId, @Param("sampleId") String sampleId);

    /**
     * How many live shipments carry this sample. Deleting a sample would cascade
     * these links away, so the service refuses while any remain.
     */
    @Select("""
            SELECT count(*)
              FROM shipment_sample ss
              JOIN shipment sh ON sh.shipment_id = ss.shipment_id
             WHERE ss.sample_id = #{sampleId} AND ss.is_deleted = false AND sh.is_deleted = false
            """)
    int countLiveLinksForSample(@Param("sampleId") String sampleId);

    @Select("""
            SELECT * FROM shipment_sample
             WHERE shipment_id = #{shipmentId} AND sample_id = #{sampleId} AND is_deleted = false
             LIMIT 1
            """)
    ShipmentSample findLink(@Param("shipmentId") String shipmentId, @Param("sampleId") String sampleId);

    record ShipmentSampleRow(
            Long shipmentSampleId, String shipmentId, String sampleId,
            String sampleCustomerSampleId, String customerSampleId,
            String description, String dateCode, String dbId,
            BigDecimal qty, String uom, String assemblyCenter,
            String testCenter, Integer numOfDies, String failureTypeName) {
    }
}
