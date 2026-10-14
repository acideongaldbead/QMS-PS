package com.nexperia.qms.rootcause;

import com.nexperia.qms.rootcause.dto.RootCauseDtos;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * D4 root-cause analysis and the 3x5Why / fishbone content (requirement 3.5).
 *
 * rootcause:edit is held by the quality engineer, matching the prototype's persona
 * hint (quality engineer: sample logistics, action tracking, root cause).
 */
@RestController
@RequestMapping("/api")
public class RootCauseController {

    private static final String MAY_EDIT = "hasAuthority('rootcause:edit')";

    private final RootCauseService rootCauseService;

    public RootCauseController(RootCauseService rootCauseService) {
        this.rootCauseService = rootCauseService;
    }

    @GetMapping("/complaints/{complaintId}/root-causes")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<RootCauseDtos.RootCauseView> list(@PathVariable String complaintId) {
        return rootCauseService.list(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/root-causes")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_EDIT)
    public RootCauseDtos.RootCauseDetail create(
            @PathVariable String complaintId,
            @Valid @RequestBody RootCauseDtos.RootCauseRequest request) {
        return rootCauseService.create(complaintId, request);
    }

    /** The entry plus the newest version of each analysis tool. */
    @GetMapping("/root-causes/{rootCauseId}")
    @PreAuthorize("hasAuthority('complaint:view')")
    public RootCauseDtos.RootCauseDetail detail(@PathVariable String rootCauseId) {
        return rootCauseService.get(rootCauseId);
    }

    @PutMapping("/root-causes/{rootCauseId}")
    @PreAuthorize(MAY_EDIT)
    public RootCauseDtos.RootCauseDetail update(
            @PathVariable String rootCauseId,
            @Valid @RequestBody RootCauseDtos.RootCauseRequest request) {
        return rootCauseService.update(rootCauseId, request);
    }

    @DeleteMapping("/root-causes/{rootCauseId}")
    @PreAuthorize(MAY_EDIT)
    public void remove(@PathVariable String rootCauseId) {
        rootCauseService.remove(rootCauseId);
    }

    /** Ownership decision and hand-over to another organisation (PS-047). */
    @PostMapping("/root-causes/{rootCauseId}/transfer")
    @PreAuthorize(MAY_EDIT)
    public RootCauseDtos.RootCauseDetail transfer(
            @PathVariable String rootCauseId,
            @Valid @RequestBody RootCauseDtos.TransferRequest request) {
        return rootCauseService.transfer(rootCauseId, request);
    }

    /** Saves a new version of the 3x5Why or fishbone content. */
    @PostMapping("/root-causes/{rootCauseId}/analysis")
    @PreAuthorize(MAY_EDIT)
    public RootCauseDtos.RootCauseDetail saveAnalysis(
            @PathVariable String rootCauseId,
            @Valid @RequestBody RootCauseDtos.AnalysisRequest request) {
        return rootCauseService.saveAnalysis(rootCauseId, request);
    }

    @GetMapping("/root-causes/{rootCauseId}/analysis/{analysisType}/versions")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<RootCauseDtos.AnalysisView> versions(@PathVariable String rootCauseId,
                                                    @PathVariable String analysisType) {
        return rootCauseService.listVersions(rootCauseId, analysisType);
    }
}
