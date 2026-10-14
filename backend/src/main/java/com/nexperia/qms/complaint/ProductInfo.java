package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/** 1:1 with a complaint (requirement 3.1.4). Shares the complaint's primary key. */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("product_info")
public class ProductInfo extends BaseEntity {

    @TableId(value = "complaint_id", type = IdType.INPUT)
    private String complaintId;

    /** 12NC / 9NC, from product master. */
    private String materialCode;

    private String productTypeCode;
    private String packingTypeCode;
    private String businessGroup;
    private String businessUnit;
    private String nc9;

    /**
     * MAG. The schema comment says "文档原文字段，含义待业务方确认" -- carried
     * through unchanged, not validated, and deliberately absent from reports
     * until the business defines it.
     */
    private String mag;

    private String customerPartNo;

    /** 4TG. Same caveat as {@link #mag}. */
    private String tg4;

    /** 5GT. Same caveat as {@link #mag}. */
    private String tg5;

    /** 6GT. Same caveat as {@link #mag}. */
    private String tg6;

    private String productStatus;
    private Boolean isProtected;
}
