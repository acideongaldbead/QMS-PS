package com.nexperia.qms.verification;

import com.nexperia.qms.verification.dto.VerificationDtos;
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
 * D2 verification and the validity conclusion (requirement 3.3).
 *
 * Recording results is a verification action, so it needs verify:edit rather than
 * complaint:edit -- that is the distinction the role matrix draws between a
 * quality engineer and a sales-quality specialist.
 */
@RestController
@RequestMapping("/api")
public class VerificationController {

    /**
     * verify:edit alone, held by the quality engineer. Adding complaint:edit here
     * would let the sales-quality role run verification too and erase the
     * distinction the role matrix draws.
     */
    private static final String MAY_VERIFY = "hasAuthority('verify:edit')";

    private final VerificationService verificationService;

    public VerificationController(VerificationService verificationService) {
        this.verificationService = verificationService;
    }

    @GetMapping("/complaints/{complaintId}/verification-tasks")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<VerificationDtos.TaskView> list(@PathVariable String complaintId) {
        return verificationService.listTasks(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/verification-tasks")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.TaskDetail create(@PathVariable String complaintId,
                                             @Valid @RequestBody VerificationDtos.TaskRequest request) {
        return verificationService.createTask(complaintId, request);
    }

    @GetMapping("/verification-tasks/{taskId}")
    @PreAuthorize("hasAuthority('complaint:view')")
    public VerificationDtos.TaskDetail detail(@PathVariable String taskId) {
        return verificationService.getTask(taskId);
    }

    @PutMapping("/verification-tasks/{taskId}")
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.TaskDetail update(@PathVariable String taskId,
                                             @Valid @RequestBody VerificationDtos.TaskRequest request) {
        return verificationService.updateTask(taskId, request);
    }

    @DeleteMapping("/verification-tasks/{taskId}")
    @PreAuthorize(MAY_VERIFY)
    public void remove(@PathVariable String taskId) {
        verificationService.removeTask(taskId);
    }

    /** Record one test line. */
    @PostMapping("/verification-tasks/{taskId}/results")
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.TaskDetail addResult(@PathVariable String taskId,
                                                 @Valid @RequestBody VerificationDtos.ResultRequest request) {
        return verificationService.addResult(taskId, request);
    }

    /** Batch summary entry: several test lines in one call. */
    @PostMapping("/verification-tasks/{taskId}/results/batch")
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.TaskDetail addBatchResults(
            @PathVariable String taskId,
            @Valid @RequestBody List<VerificationDtos.ResultRequest> requests) {
        return verificationService.addBatchResults(taskId, requests);
    }

    @DeleteMapping("/verification-tasks/{taskId}/results/{resultId}")
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.TaskDetail removeResult(@PathVariable String taskId,
                                                    @PathVariable long resultId) {
        return verificationService.removeResult(taskId, resultId);
    }

    /**
     * The D2 conclusion. A "not valid" answer closes the complaint, which is the
     * branch requirement 2.1 describes.
     */
    @PostMapping("/complaints/{complaintId}/validity")
    @PreAuthorize(MAY_VERIFY)
    public VerificationDtos.ValidityResult setValidity(
            @PathVariable String complaintId,
            @Valid @RequestBody VerificationDtos.ValidityRequest request) {
        return verificationService.setValidity(complaintId, request);
    }
}
