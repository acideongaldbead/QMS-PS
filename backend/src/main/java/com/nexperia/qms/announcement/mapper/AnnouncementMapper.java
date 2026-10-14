package com.nexperia.qms.announcement.mapper;

import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

@Mapper
public interface AnnouncementMapper {

    /**
     * Published announcements, newest first, for the home page.
     *
     * publish_status is free text with the baseline's three values rather than a
     * dictionary table, so the filter compares the stored Chinese value directly
     * (the JDBC connection is UTF-8; only the psql command line cannot carry it).
     *
     * The select list order must match the components of AnnouncementView: MyBatis
     * maps a constructor by column position, not by name.
     */
    @Select("""
            SELECT a.announcement_id AS announcementId,
                   a.title           AS title,
                   a.content         AS content,
                   a.published_at    AS publishedAt,
                   e.name            AS publishedByName,
                   (r.announcement_id IS NULL) AS isNew
              FROM system_announcement a
              LEFT JOIN employee          e ON e.employee_id = a.published_by
              LEFT JOIN announcement_read r ON r.announcement_id = a.announcement_id
                                           AND r.employee_id = #{me}
             WHERE a.is_deleted = false
               AND a.publish_status = '已发布'
             ORDER BY a.published_at DESC NULLS LAST, a.announcement_id DESC
             LIMIT #{limit}
            """)
    List<AnnouncementDtos.AnnouncementView> findPublished(@Param("limit") int limit, @Param("me") String me);

    /** Idempotent: a second click on the same announcement must not fail. */
    @Insert("""
            INSERT INTO announcement_read (announcement_id, employee_id, read_at)
            VALUES (#{announcementId}, #{employeeId}, now())
            ON CONFLICT (announcement_id, employee_id) DO NOTHING
            """)
    int markRead(@Param("announcementId") long announcementId, @Param("employeeId") String employeeId);

    @Select("""
            SELECT count(*) FROM system_announcement
             WHERE announcement_id = #{announcementId} AND is_deleted = false
            """)
    int countAnnouncement(@Param("announcementId") long announcementId);
}
