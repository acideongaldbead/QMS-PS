package com.nexperia.qms.announcement;

import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import com.nexperia.qms.announcement.mapper.AnnouncementMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.richtext.HtmlSanitizer;
import com.nexperia.qms.common.security.CurrentUserContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;

/**
 * The home page's announcement list (requirement 3.0) and the management screen
 * that maintains it.
 *
 * Reading is open to anyone logged in: every role sees the home page and an
 * announcement is exactly what the whole company is meant to read. Maintenance
 * (create / edit / publish / retire / delete) needs {@code announcement:manage}.
 *
 * The body is sanitised HTML: every write runs it through {@link HtmlSanitizer},
 * and reads return the stored string untouched so the markup round-trips byte for
 * byte. publish_status carries the baseline's three values (草稿 / 已发布 / 已下架);
 * the home page only ever shows 已发布.
 */
@Service
public class AnnouncementService {

    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    static final String STATUS_DRAFT = "草稿";
    static final String STATUS_PUBLISHED = "已发布";
    static final String STATUS_RETIRED = "已下架";

    private static final String BIZ_TYPE = "Announcement";

    private final AnnouncementMapper announcementMapper;
    private final HtmlSanitizer htmlSanitizer;
    private final AuditLogService auditLogService;

    public AnnouncementService(AnnouncementMapper announcementMapper,
                               HtmlSanitizer htmlSanitizer,
                               AuditLogService auditLogService) {
        this.announcementMapper = announcementMapper;
        this.htmlSanitizer = htmlSanitizer;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<AnnouncementDtos.AnnouncementView> published(Integer limit) {
        int capped = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);
        return announcementMapper.findPublished(capped, CurrentUserContext.employeeId());
    }

    /**
     * Records that the current user has opened an announcement, which is what
     * clears its NEW badge. Idempotent, so a double click is not an error.
     */
    @Transactional
    public void markRead(long announcementId) {
        if (announcementMapper.countAnnouncement(announcementId) == 0) {
            throw new NotFoundException("公告不存在：" + announcementId);
        }
        announcementMapper.markRead(announcementId, CurrentUserContext.employeeId());
    }

    // ------------------------------------------------------------- management

    @Transactional(readOnly = true)
    public List<AnnouncementDtos.ManageView> manageList(String status) {
        return announcementMapper.findManage(trimToNull(status));
    }

    @Transactional(readOnly = true)
    public AnnouncementDtos.ManageView manageGet(long announcementId) {
        AnnouncementDtos.ManageView view = announcementMapper.findManageById(announcementId);
        if (view == null) {
            throw new NotFoundException("公告不存在：" + announcementId);
        }
        return view;
    }

    @Transactional
    public AnnouncementDtos.ManageView manageCreate(AnnouncementDtos.SaveRequest request) {
        Announcement announcement = new Announcement();
        announcement.setTitle(request.title().trim());
        String content = htmlSanitizer.sanitize(request.content());
        requireContent(content);
        announcement.setContent(content);
        announcement.setPublishStatus(STATUS_DRAFT);
        announcement.setPublishedAt(toOffset(request.publishedAt()));
        announcementMapper.insert(announcement);

        auditLogService.record(AuditActions.CREATE, BIZ_TYPE,
                String.valueOf(announcement.getAnnouncementId()),
                "新增系统公告：" + announcement.getTitle());
        return manageGet(announcement.getAnnouncementId());
    }

    /**
     * Editing is allowed in any status, including 已发布: the lifecycle governs
     * visibility, not the text, and the administrator may correct a live notice or
     * back-date its time. The audit entry keeps the change traceable.
     */
    @Transactional
    public AnnouncementDtos.ManageView manageUpdate(long announcementId, AnnouncementDtos.SaveRequest request) {
        Announcement before = requireRow(announcementId);
        String title = request.title().trim();
        String content = htmlSanitizer.sanitize(request.content());
        requireContent(content);
        announcementMapper.updateContent(announcementId, title, content,
                toOffset(request.publishedAt()), CurrentUserContext.employeeId());

        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_TYPE, String.valueOf(announcementId),
                describe(before.getTitle(), before.getPublishStatus()),
                describe(title, before.getPublishStatus()));
        return manageGet(announcementId);
    }

    @Transactional
    public AnnouncementDtos.ManageView managePublish(long announcementId) {
        Announcement row = requireRow(announcementId);
        if (STATUS_PUBLISHED.equals(row.getPublishStatus())) {
            throw new IllegalStateException("公告已是发布状态：" + announcementId);
        }
        OffsetDateTime when = row.getPublishedAt() != null ? row.getPublishedAt() : OffsetDateTime.now();
        announcementMapper.publish(announcementId, CurrentUserContext.employeeId(), when);

        auditLogService.record(AuditActions.STATUS_CHANGE, BIZ_TYPE, String.valueOf(announcementId),
                "公告发布：" + row.getTitle());
        return manageGet(announcementId);
    }

    @Transactional
    public AnnouncementDtos.ManageView manageRetire(long announcementId) {
        Announcement row = requireRow(announcementId);
        if (!STATUS_PUBLISHED.equals(row.getPublishStatus())) {
            throw new IllegalStateException("只有已发布的公告可以下架：" + announcementId);
        }
        announcementMapper.retire(announcementId, CurrentUserContext.employeeId());

        auditLogService.record(AuditActions.STATUS_CHANGE, BIZ_TYPE, String.valueOf(announcementId),
                "公告下架：" + row.getTitle());
        return manageGet(announcementId);
    }

    @Transactional
    public void manageDelete(long announcementId) {
        Announcement row = requireRow(announcementId);
        announcementMapper.softDelete(announcementId, CurrentUserContext.employeeId());
        auditLogService.record(AuditActions.DELETE, BIZ_TYPE, String.valueOf(announcementId),
                "删除系统公告：" + row.getTitle());
    }

    private Announcement requireRow(long announcementId) {
        Announcement row = announcementMapper.selectById(announcementId);
        if (row == null) {
            throw new NotFoundException("公告不存在：" + announcementId);
        }
        return row;
    }

    /**
     * A body of only empty paragraphs ({@code <p></p>}) passes the bean-validation
     * blank check but reads as nothing, so the sanitised HTML is checked for real
     * content before it is stored.
     */
    private void requireContent(String html) {
        String text = html == null ? "" : html.replaceAll("<[^>]*>", "").replace("&nbsp;", " ").trim();
        if (text.isEmpty()) {
            throw new IllegalArgumentException("内容不能为空");
        }
    }

    /**
     * The form field is a wall-clock time; the column is timestamptz. Convert it at
     * the server's zone so a back-dated notice reads as the administrator typed it.
     */
    private OffsetDateTime toOffset(LocalDateTime value) {
        return value == null ? null : value.atZone(ZoneId.systemDefault()).toOffsetDateTime();
    }

    private String describe(String title, String status) {
        return "标题=" + title + "；状态=" + status;
    }

    private String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
