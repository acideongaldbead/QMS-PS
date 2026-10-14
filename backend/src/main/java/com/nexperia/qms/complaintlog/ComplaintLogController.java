package com.nexperia.qms.complaintlog;

import com.nexperia.qms.complaintlog.dto.ComplaintLogDtos;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * The complaint detail page's "沟通与流程日志" tab.
 *
 * Read-only, and gated the same way the complaint itself is: whoever may read the
 * complaint may read its history.
 */
@RestController
@RequestMapping("/api/complaints")
public class ComplaintLogController {

    private final ComplaintLogService complaintLogService;

    public ComplaintLogController(ComplaintLogService complaintLogService) {
        this.complaintLogService = complaintLogService;
    }

    @GetMapping("/{complaintId}/logs")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<ComplaintLogDtos.LogEntry> logs(@PathVariable String complaintId) {
        return complaintLogService.entries(complaintId);
    }
}
