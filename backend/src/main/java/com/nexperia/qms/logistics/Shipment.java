package com.nexperia.qms.logistics;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;
import java.time.LocalDate;

/** One shipment of failed parts for a complaint (requirement 3.2.1). */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("shipment")
public class Shipment extends BaseEntity {

    @TableId(value = "shipment_id", type = IdType.INPUT)
    private String shipmentId;

    private String complaintId;

    private String senderId;
    private String receiverId;

    /** Free-text carrier waybill number, called Shipment ID in the requirement. */
    private String shipmentNo;

    /** One of {@link ShipmentStatus}. */
    private String shipmentStatus;

    private BigDecimal quantityPartsShipped;

    /** Yes / No. */
    private String application;

    private LocalDate startDate;

    private String carrierName;
    private String carrierTrackingNumber;
    private LocalDate targetDate;
    private LocalDate closeDate;
    private String comments;
}
