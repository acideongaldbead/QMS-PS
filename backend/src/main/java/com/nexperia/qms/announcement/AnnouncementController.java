package com.nexperia.qms.announcement;

import com.nexperia.qms.announcement.dto.AnnouncementDtos;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * The home page's system announcements (requirement 3.0).
 *
 * Reading needs no authority beyond being logged in: every role sees the home
 * page, and an announcement is exactly the thing the whole company is meant to
 * read. The {@code /manage} sub-namespace needs {@code announcement:manage}
 * (the administrator) and drives the standalone management screen.
 */
@RestController
@RequestMapping("/api/announcements")
public class AnnouncementController {

    private static final String MAY_MANAGE = "hasAuthority('announcement:manage')";

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

    // ------------------------------------------------------------- management

    /** Every announcement, any status, newest publish time first. */
    @GetMapping("/manage")
    @PreAuthorize(MAY_MANAGE)
    public List<AnnouncementDtos.ManageView> manageList(
            @RequestParam(required = false) String status) {
        return announcementService.manageList(status);
    }

    @GetMapping("/manage/{announcementId}")
    @PreAuthorize(MAY_MANAGE)
    public AnnouncementDtos.ManageView manageGet(@PathVariable long announcementId) {
        return announcementService.manageGet(announcementId);
    }

    /** Created as a draft; publishing is a separate step. */
    @PostMapping("/manage")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_MANAGE)
    public AnnouncementDtos.ManageView manageCreate(@Valid @RequestBody AnnouncementDtos.SaveRequest request) {
        return announcementService.manageCreate(request);
    }

    @PutMapping("/manage/{announcementId}")
    @PreAuthorize(MAY_MANAGE)
    public AnnouncementDtos.ManageView manageUpdate(@PathVariable long announcementId,
                                                    @Valid @RequestBody AnnouncementDtos.SaveRequest request) {
        return announcementService.manageUpdate(announcementId, request);
    }

    @PostMapping("/manage/{announcementId}/publish")
    @PreAuthorize(MAY_MANAGE)
    public AnnouncementDtos.ManageView managePublish(@PathVariable long announcementId) {
        return announcementService.managePublish(announcementId);
    }

    @PostMapping("/manage/{announcementId}/retire")
    @PreAuthorize(MAY_MANAGE)
    public AnnouncementDtos.ManageView manageRetire(@PathVariable long announcementId) {
        return announcementService.manageRetire(announcementId);
    }

    @DeleteMapping("/manage/{announcementId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize(MAY_MANAGE)
    public void manageDelete(@PathVariable long announcementId) {
        announcementService.manageDelete(announcementId);
    }
}
