package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;

/** A customer sample under a complaint; one complaint can carry many (requirement 3.1.6). */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("sample")
public class Sample extends BaseEntity {

    @TableId(value = "sample_id", type = IdType.INPUT)
    private String sampleId;

    private String complaintId;
    private String customerSampleId;

    /** Sent by Sales Quality to the customer and recorded when the sample arrives. */
    private String champId;

    private BigDecimal sampleQuantity;
    private String uom;
    private String description;
    private String productMarking;
    private String applicationArea;
    private Boolean rejectConfirmed;
    private String conclusion;

    /** Three-level failure type; L2 must sit under L1 and L3 under L2. */
    private String failureTypeL1Code;
    private String failureTypeL2Code;
    private String failureTypeL3Code;
}
