package com.nexperia.qms.complaint;

import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * Samples edited after registration. Registering a complaint creates its samples
 * in the same transaction; these endpoints cover parts that arrive later and
 * corrections (requirement 3.1.6).
 */
@RestController
@RequestMapping("/api/complaints/{complaintId}/samples")
public class SampleController {

    private final SampleService sampleService;

    public SampleController(SampleService sampleService) {
        this.sampleService = sampleService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasAnyAuthority('sample:edit','complaint:edit')")
    public ComplaintResponses.CreatedSample add(@PathVariable String complaintId,
                                               @Valid @RequestBody ComplaintRequests.Sample form) {
        return new ComplaintResponses.CreatedSample(sampleService.add(complaintId, form));
    }

    @PutMapping("/{sampleId}")
    @PreAuthorize("hasAnyAuthority('sample:edit','complaint:edit')")
    public void update(@PathVariable String complaintId,
                       @PathVariable String sampleId,
                       @Valid @RequestBody ComplaintRequests.Sample form) {
        sampleService.update(complaintId, sampleId, form);
    }

    @DeleteMapping("/{sampleId}")
    @PreAuthorize("hasAnyAuthority('sample:edit','complaint:edit')")
    public void remove(@PathVariable String complaintId, @PathVariable String sampleId) {
        sampleService.remove(complaintId, sampleId);
    }
}
