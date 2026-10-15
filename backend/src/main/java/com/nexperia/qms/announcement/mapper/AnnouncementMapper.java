package com.nexperia.qms.announcement.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.announcement.Announcement;
import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.OffsetDateTime;
import java.util.List;

@Mapper
public interface AnnouncementMapper extends BaseMapper<Announcement> {

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

    // ---------------------------------------------------------- management
    // The select-list order below must match the components of ManageView: MyBatis
    // maps a record by column position, not by name. Both sides are numbered.

    /** Every non-deleted announcement, optionally filtered by status. */
    @Select("""
            <script>
            SELECT a.announcement_id AS announcementId,  -- 1
                   a.title           AS title,           -- 2
                   a.content         AS content,         -- 3
                   a.publish_status  AS publishStatus,   -- 4
                   a.published_at    AS publishedAt,     -- 5
                   e.name            AS publishedByName, -- 6
                   a.updated_at      AS updatedAt,       -- 7
                   u.name            AS updatedByName    -- 8
              FROM system_announcement a
              LEFT JOIN employee e ON e.employee_id = a.published_by
              LEFT JOIN employee u ON u.employee_id = a.updated_by
             WHERE a.is_deleted = false
            <if test="status != null and status != ''">
               AND a.publish_status = #{status}
            </if>
             ORDER BY a.published_at DESC NULLS LAST, a.announcement_id DESC
            </script>
            """)
    List<AnnouncementDtos.ManageView> findManage(@Param("status") String status);

    /** One announcement, or null when it does not exist / is deleted. */
    @Select("""
            SELECT a.announcement_id AS announcementId,  -- 1
                   a.title           AS title,           -- 2
                   a.content         AS content,         -- 3
                   a.publish_status  AS publishStatus,   -- 4
                   a.published_at    AS publishedAt,     -- 5
                   e.name            AS publishedByName, -- 6
                   a.updated_at      AS updatedAt,       -- 7
                   u.name            AS updatedByName    -- 8
              FROM system_announcement a
              LEFT JOIN employee e ON e.employee_id = a.published_by
              LEFT JOIN employee u ON u.employee_id = a.updated_by
             WHERE a.is_deleted = false
               AND a.announcement_id = #{announcementId}
            """)
    AnnouncementDtos.ManageView findManageById(@Param("announcementId") long announcementId);

    /**
     * Explicit UPDATEs rather than MyBatis-Plus {@code updateById}, which skips
     * null fields: clearing the published time would then report success while the
     * old value stayed in the row. updated_at is maintained by the baseline trigger.
     */
    @Update("""
            UPDATE system_announcement
               SET title        = #{title},
                   content      = #{content},
                   published_at = #{publishedAt},
                   updated_by   = #{operator}
             WHERE announcement_id = #{announcementId} AND is_deleted = false
            """)
    int updateContent(@Param("announcementId") long announcementId,
                      @Param("title") String title,
                      @Param("content") String content,
                      @Param("publishedAt") OffsetDateTime publishedAt,
                      @Param("operator") String operator);

    /** Publish (or re-publish), stamping the publisher and the publish time. */
    @Update("""
            UPDATE system_announcement
               SET publish_status = '已发布',
                   published_by   = #{operator},
                   published_at   = #{publishedAt},
                   updated_by     = #{operator}
             WHERE announcement_id = #{announcementId} AND is_deleted = false
            """)
    int publish(@Param("announcementId") long announcementId,
                @Param("operator") String operator,
                @Param("publishedAt") OffsetDateTime publishedAt);

    /** Take a published announcement off the home page. */
    @Update("""
            UPDATE system_announcement
               SET publish_status = '已下架',
                   updated_by     = #{operator}
             WHERE announcement_id = #{announcementId} AND is_deleted = false
            """)
    int retire(@Param("announcementId") long announcementId,
               @Param("operator") String operator);

    @Update("""
            UPDATE system_announcement
               SET is_deleted = true,
                   updated_by = #{operator}
             WHERE announcement_id = #{announcementId}
            """)
    int softDelete(@Param("announcementId") long announcementId,
                   @Param("operator") String operator);
}
