package com.nexperia.qms.announcement;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.OffsetDateTime;

/**
 * A system announcement (requirement 3.0): what the home page shows and what the
 * {@code announcement:manage} screen maintains.
 *
 * Only the create path uses the entity, so {@code insert} can hand back the
 * generated id; reads go through the mapper's own projections and every write is
 * an explicit UPDATE (MyBatis-Plus {@code updateById} would skip null fields).
 *
 * {@code publishStatus} is free text carrying the baseline's three values:
 * 草稿 / 已发布 / 已下架. {@code content} holds sanitised HTML.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("system_announcement")
public class Announcement extends BaseEntity {

    @TableId(value = "announcement_id", type = IdType.AUTO)
    private Long announcementId;

    private String title;

    /** Sanitised HTML (see HtmlSanitizer); rendered with v-html. */
    private String content;

    private String publishStatus;

    private String publishedBy;

    /** Maintained by the administrator; defaults to now on publish when unset. */
    private OffsetDateTime publishedAt;
}
