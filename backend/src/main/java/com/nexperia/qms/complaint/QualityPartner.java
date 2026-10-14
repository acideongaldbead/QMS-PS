package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/** 1:1 with a complaint (requirement 3.1.3). Shares the complaint's primary key. */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("quality_partner")
public class QualityPartner extends BaseEntity {

    @TableId(value = "complaint_id", type = IdType.INPUT)
    private String complaintId;

    /** Customer master data; cannot be created on the fly from this screen. */
    private String qualityPartnerCode;

    /** Yes / No. */
    private String application;

    /** Becomes the addressee when the 8D report is sent. */
    private String contactPersonId;

    private String hsCode;
    private String endCustomer;
    private String eccn;

    /** Pre-filled from the customer, editable. */
    private String subSegmentCode;

    private String shipToSoldToCode;
}
