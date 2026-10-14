package com.nexperia.qms.actions;

import com.nexperia.qms.actions.dto.ActionDtos;
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
 * D5 corrective actions and their D6 verification, plus D7 prevention files
 * (requirements 3.6 to 3.8).
 *
 * Three distinct permissions, matching the role matrix: action:edit to run the
 * corrective actions, action:verify to judge their effectiveness, prevention:edit
 * to maintain the D7 document list.
 */
@RestController
@RequestMapping("/api")
public class ActionsController {

    private static final String MAY_EDIT_ACTION = "hasAuthority('action:edit')";
    private static final String MAY_VERIFY = "hasAuthority('action:verify')";
    private static final String MAY_EDIT_PREVENTION = "hasAuthority('prevention:edit')";

    private final CorrectiveActionService correctiveActionService;
    private final PreventionService preventionService;

    public ActionsController(CorrectiveActionService correctiveActionService,
                             PreventionService preventionService) {
        this.correctiveActionService = correctiveActionService;
        this.preventionService = preventionService;
    }

    // ------------------------------------------------------------- D5 / D6

    @GetMapping("/complaints/{complaintId}/corrective-actions")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<ActionDtos.CorrectiveActionView> listActions(@PathVariable String complaintId) {
        return correctiveActionService.list(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/corrective-actions")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_EDIT_ACTION)
    public ActionDtos.CorrectiveActionDetail createAction(
            @PathVariable String complaintId,
            @Valid @RequestBody ActionDtos.CorrectiveActionRequest request) {
        return correctiveActionService.create(complaintId, request);
    }

    @GetMapping("/corrective-actions/{actionId}")
    @PreAuthorize("hasAuthority('complaint:view')")
    public ActionDtos.CorrectiveActionDetail actionDetail(@PathVariable String actionId) {
        return correctiveActionService.get(actionId);
    }

    @PutMapping("/corrective-actions/{actionId}")
    @PreAuthorize(MAY_EDIT_ACTION)
    public ActionDtos.CorrectiveActionDetail updateAction(
            @PathVariable String actionId,
            @Valid @RequestBody ActionDtos.CorrectiveActionRequest request) {
        return correctiveActionService.update(actionId, request);
    }

    @DeleteMapping("/corrective-actions/{actionId}")
    @PreAuthorize(MAY_EDIT_ACTION)
    public void removeAction(@PathVariable String actionId) {
        correctiveActionService.remove(actionId);
    }

    /** D6: records implementation progress and the effectiveness judgement. */
    @PostMapping("/corrective-actions/{actionId}/verifications")
    @PreAuthorize(MAY_VERIFY)
    public ActionDtos.CorrectiveActionDetail addVerification(
            @PathVariable String actionId,
            @Valid @RequestBody ActionDtos.VerificationRequest request) {
        return correctiveActionService.addVerification(actionId, request);
    }

    @DeleteMapping("/corrective-actions/{actionId}/verifications/{verificationId}")
    @PreAuthorize(MAY_VERIFY)
    public ActionDtos.CorrectiveActionDetail removeVerification(
            @PathVariable String actionId,
            @PathVariable long verificationId) {
        return correctiveActionService.removeVerification(actionId, verificationId);
    }

    // ------------------------------------------------------------- D7

    @GetMapping("/complaints/{complaintId}/prevention-files")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<ActionDtos.PreventionView> listPrevention(@PathVariable String complaintId) {
        return preventionService.list(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/prevention-files")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_EDIT_PREVENTION)
    public List<ActionDtos.PreventionView> createPrevention(
            @PathVariable String complaintId,
            @Valid @RequestBody ActionDtos.PreventionRequest request) {
        return preventionService.create(complaintId, request);
    }

    @PutMapping("/prevention-files/{updateId}")
    @PreAuthorize(MAY_EDIT_PREVENTION)
    public List<ActionDtos.PreventionView> updatePrevention(
            @PathVariable long updateId,
            @Valid @RequestBody ActionDtos.PreventionRequest request) {
        return preventionService.update(updateId, request);
    }

    @DeleteMapping("/prevention-files/{updateId}")
    @PreAuthorize(MAY_EDIT_PREVENTION)
    public List<ActionDtos.PreventionView> removePrevention(@PathVariable long updateId) {
        return preventionService.remove(updateId);
    }
}
