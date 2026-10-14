package com.nexperia.qms.logistics.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.logistics.Shipment;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface ShipmentMapper extends BaseMapper<Shipment> {

    /**
     * Shipments of a complaint with the names and the sample count resolved, so
     * the list needs no extra round trips.
     */
    @Select("""
            SELECT s.shipment_id AS shipmentId, s.complaint_id AS complaintId,
                   s.sender_id AS senderId, es.name AS senderName,
                   s.receiver_id AS receiverId, er.name AS receiverName,
                   s.shipment_no AS shipmentNo,
                   s.shipment_status AS shipmentStatus, sc.name_cn AS shipmentStatusName,
                   s.quantity_parts_shipped AS quantityPartsShipped, s.application AS application,
                   s.start_date AS startDate, s.carrier_name AS carrierName,
                   s.carrier_tracking_number AS carrierTrackingNumber,
                   s.target_date AS targetDate, s.close_date AS closeDate, s.comments AS comments,
                   s.created_by AS createdBy, eo.name AS createdByName, s.created_at AS createdAt,
                   (SELECT count(*) FROM shipment_sample ss
                     WHERE ss.shipment_id = s.shipment_id AND ss.is_deleted = false) AS sampleCount
              FROM shipment s
              LEFT JOIN employee es ON es.employee_id = s.sender_id
              LEFT JOIN employee er ON er.employee_id = s.receiver_id
              LEFT JOIN employee eo ON eo.employee_id = s.created_by
              LEFT JOIN status_code sc ON sc.status_code = s.shipment_status
             WHERE s.complaint_id = #{complaintId} AND s.is_deleted = false
             ORDER BY s.created_at DESC, s.shipment_id DESC
            """)
    List<ShipmentRow> findByComplaint(@Param("complaintId") String complaintId);

    @Select("""
            SELECT s.shipment_id AS shipmentId, s.complaint_id AS complaintId,
                   s.sender_id AS senderId, es.name AS senderName,
                   s.receiver_id AS receiverId, er.name AS receiverName,
                   s.shipment_no AS shipmentNo,
                   s.shipment_status AS shipmentStatus, sc.name_cn AS shipmentStatusName,
                   s.quantity_parts_shipped AS quantityPartsShipped, s.application AS application,
                   s.start_date AS startDate, s.carrier_name AS carrierName,
                   s.carrier_tracking_number AS carrierTrackingNumber,
                   s.target_date AS targetDate, s.close_date AS closeDate, s.comments AS comments,
                   s.created_by AS createdBy, eo.name AS createdByName, s.created_at AS createdAt,
                   (SELECT count(*) FROM shipment_sample ss
                     WHERE ss.shipment_id = s.shipment_id AND ss.is_deleted = false) AS sampleCount
              FROM shipment s
              LEFT JOIN employee es ON es.employee_id = s.sender_id
              LEFT JOIN employee er ON er.employee_id = s.receiver_id
              LEFT JOIN employee eo ON eo.employee_id = s.created_by
              LEFT JOIN status_code sc ON sc.status_code = s.shipment_status
             WHERE s.shipment_id = #{shipmentId} AND s.is_deleted = false
            """)
    ShipmentRow findRow(@Param("shipmentId") String shipmentId);

    /** Every component needs a matching column: MyBatis builds records via the constructor. */
    record ShipmentRow(
            String shipmentId, String complaintId,
            String senderId, String senderName,
            String receiverId, String receiverName,
            String shipmentNo, String shipmentStatus, String shipmentStatusName,
            BigDecimal quantityPartsShipped, String application,
            LocalDate startDate, String carrierName, String carrierTrackingNumber,
            LocalDate targetDate, LocalDate closeDate, String comments,
            String createdBy, String createdByName, OffsetDateTime createdAt,
            Integer sampleCount) {
    }
}
