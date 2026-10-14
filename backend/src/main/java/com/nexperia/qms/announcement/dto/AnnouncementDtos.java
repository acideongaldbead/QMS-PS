package com.nexperia.qms.announcement.dto;

import java.time.OffsetDateTime;

public final class AnnouncementDtos {

    private AnnouncementDtos() {
    }

    /**
     * A published announcement as the home page shows it. The body travels with
     * the list because the drawer opens it without a second round trip.
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
}
