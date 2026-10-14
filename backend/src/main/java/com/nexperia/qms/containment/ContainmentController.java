package com.nexperia.qms.containment;

import com.nexperia.qms.containment.dto.ContainmentDtos;
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

/**
 * D3 containment actions and the decision on whether they are needed at all
 * (requirement 3.4, PS-039 to PS-041).
 *
 * containment:edit is held by the quality engineer, matching the prototype's
 * persona hints (quality engineer: sample logistics, action tracking, root cause).
 */
@RestController
@RequestMapping("/api")
public class ContainmentController {

    private static final String MAY_EDIT = "hasAuthority('containment:edit')";

    private final ContainmentService containmentService;

    public ContainmentController(ContainmentService containmentService) {
        this.containmentService = containmentService;
    }

    /** The decision plus the actions, in one read: the tab shows them together. */
    @GetMapping("/complaints/{complaintId}/containment")
    @PreAuthorize("hasAuthority('complaint:view')")
    public ContainmentDtos.ContainmentSummary summary(@PathVariable String complaintId) {
        return containmentService.summary(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/containment/decision")
    @PreAuthorize(MAY_EDIT)
    public ContainmentDtos.ContainmentSummary decide(
            @PathVariable String complaintId,
            @Valid @RequestBody ContainmentDtos.DecisionRequest request) {
        return containmentService.decide(complaintId, request);
    }

    @PostMapping("/complaints/{complaintId}/containment/actions")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_EDIT)
    public ContainmentDtos.ContainmentSummary createAction(
            @PathVariable String complaintId,
            @Valid @RequestBody ContainmentDtos.ActionRequest request) {
        return containmentService.createAction(complaintId, request);
    }

    @PutMapping("/containment-actions/{actionId}")
    @PreAuthorize(MAY_EDIT)
    public ContainmentDtos.ContainmentSummary updateAction(
            @PathVariable String actionId,
            @Valid @RequestBody ContainmentDtos.ActionRequest request) {
        return containmentService.updateAction(actionId, request);
    }

    @DeleteMapping("/containment-actions/{actionId}")
    @PreAuthorize(MAY_EDIT)
    public ContainmentDtos.ContainmentSummary removeAction(@PathVariable String actionId) {
        return containmentService.removeAction(actionId);
    }
}
