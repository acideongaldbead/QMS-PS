package com.nexperia.qms.logistics;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;

/**
 * Joins a sample to a shipment, carrying the per-batch attributes requirement
 * 3.2.2 lists (Date Code, DB ID, Assembly Center, Test Center, #of Dies...).
 *
 * Those attributes live here rather than on {@code sample} because the same
 * physical sample can travel in more than one batch with different codes.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("shipment_sample")
public class ShipmentSample extends BaseEntity {

    @TableId(value = "shipment_sample_id", type = IdType.AUTO)
    private Long shipmentSampleId;

    private String shipmentId;
    private String sampleId;

    private String description;
    private String dateCode;

    /** Die Bank identifier. */
    private String dbId;

    private BigDecimal qty;
    private String uom;
    private String customerSampleId;
    private String assemblyCenter;
    private String testCenter;
    private Integer numOfDies;
}
