package com.nexperia.qms.announcement.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;
import java.time.OffsetDateTime;

public final class AnnouncementDtos {

    private AnnouncementDtos() {
    }

    /**
     * A published announcement as the home page shows it. The body travels with
     * the list because the drawer opens it without a second round trip. The body
     * is sanitised HTML, rendered with v-html.
     *
     * Component order must match the select list in AnnouncementMapper: MyBatis
     * maps a constructor by column position, not by name, unless the mapping is
     * explicitly named.
     */
    public record AnnouncementView(
            long announcementId,
            String title,
            String content,
            OffsetDateTime publishedAt,
            String publishedByName,
            /** True while this reader has never opened it - the NEW badge. */
            boolean isNew) {
    }

    /**
     * One announcement as the management screen lists it: every status, not just
     * published.
     *
     * Component order must match the select list in AnnouncementMapper.findManage
     * / findManageById (MyBatis maps by column position, not by name); both sides
     * are numbered so a new column cannot silently shift the rest.
     */
    public record ManageView(
            long announcementId,        // 1
            String title,               // 2
            String content,             // 3
            String publishStatus,       // 4
            OffsetDateTime publishedAt, // 5
            String publishedByName,     // 6
            OffsetDateTime updatedAt,   // 7
            String updatedByName) {     // 8
    }

    /**
     * Create and update share one shape; the id travels in the path.
     *
     * {@code publishedAt} is optional: left empty, the announcement is published
     * with the current time. It stays editable afterwards so a history notice can
     * be back-dated.
     */
    public record SaveRequest(
            @NotBlank(message = "标题不能为空")
            @Size(max = 255, message = "标题不能超过 255 个字符")
            String title,
            @NotBlank(message = "内容不能为空")
            String content,
            LocalDateTime publishedAt) {
    }
}
