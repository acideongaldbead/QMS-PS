package com.nexperia.qms.announcement;

import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import com.nexperia.qms.announcement.mapper.AnnouncementMapper;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * The home page's announcement list (requirement 3.0).
 *
 * Read-only apart from the read marker that drives the NEW badge: publishing and
 * retiring announcements is the {@code announcement:manage} screen, which is a
 * later task.
 */
@Service
public class AnnouncementService {

    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    private final AnnouncementMapper announcementMapper;

    public AnnouncementService(AnnouncementMapper announcementMapper) {
        this.announcementMapper = announcementMapper;
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
}
