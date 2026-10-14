package com.nexperia.qms.actions;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * A D7 file that has to be updated so the failure cannot recur (requirement 3.8):
 * FMEA, Control Plan, OCAP, SOP, Update on Flow.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("prevention_file_update")
public class PreventionFileUpdate extends BaseEntity {

    @TableId(value = "update_id", type = IdType.AUTO)
    private Long updateId;

    private String complaintId;

    private String nexSampleNumber;
    private String customerSampleId;

    /** FILE_TYPE_001..005 in master_data_item. */
    private String fileTypeCode;

    private String controlProgram;
    private String referenceNumber;

    /** One of {@link PreventionStatus}. */
    private String statusCode;
}
