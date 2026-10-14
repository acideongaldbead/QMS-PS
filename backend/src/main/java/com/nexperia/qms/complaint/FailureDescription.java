package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;

/** Failure symptoms and the commercial detail (requirement 3.1.5). 1:1 with a complaint. */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("failure_description")
public class FailureDescription extends BaseEntity {

    @TableId(value = "complaint_id", type = IdType.INPUT)
    private String complaintId;

    private String customerFailureDescription;

    /** Required: the customer's stated failure mode, from the dictionary. */
    private String customerFailureModeCode;

    private String d0SymptomsDescription;
    private String comment;

    private BigDecimal quantityFailing;
    private String quantityFailingUom;
    private BigDecimal qualityReturned;
    private String qualityReturnedUom;

    private String customerPo;
    private String salesOrder;
    private String supplierInvoiceNumber;
    private Boolean shippedDirectly;
    private String directCommunication;
    private String receivedApprPack;
    private String analysisConclusion;
}
