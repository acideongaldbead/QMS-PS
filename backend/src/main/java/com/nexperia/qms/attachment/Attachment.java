package com.nexperia.qms.attachment;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.OffsetDateTime;

/** One uploaded file, attached to any business record via biz_type + biz_id. */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("attachment")
public class Attachment extends BaseEntity {

    @TableId(value = "attachment_id", type = IdType.AUTO)
    private Long attachmentId;

    private String bizType;
    private String bizId;

    /** The name the user uploaded; kept for display and download. */
    private String fileName;

    private Long fileSize;

    /** The content type Tika detected, which may differ from the extension. */
    private String fileType;

    /** Opaque storage key, never a URL the client can construct. */
    private String storagePath;

    private String uploadedBy;
    private OffsetDateTime uploadedAt;
}
