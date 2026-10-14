package com.nexperia.qms.announcement;

import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * The home page's system announcements (requirement 3.0).
 *
 * No authority is required beyond being logged in: every role sees the home
 * page, and an announcement is exactly the thing the whole company is meant to
 * read. Publishing them needs {@code announcement:manage} and is not wired yet.
 */
@RestController
@RequestMapping("/api/announcements")
public class AnnouncementController {

    private final AnnouncementService announcementService;

    public AnnouncementController(AnnouncementService announcementService) {
        this.announcementService = announcementService;
    }

    @GetMapping
    public List<AnnouncementDtos.AnnouncementView> list(
            @RequestParam(required = false) Integer limit) {
        return announcementService.published(limit);
    }

    /** Clears the NEW badge for the current user, once. */
    @PostMapping("/{announcementId}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void markRead(@PathVariable long announcementId) {
        announcementService.markRead(announcementId);
    }
}
