package com.nexperia.qms.complaint;

import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;

@RestController
@RequestMapping("/api/complaints")
public class ComplaintController {

    private static final String MAY_VIEW = "hasAuthority('complaint:view')";

    private static final String XLSX_MIME =
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    private final ComplaintService complaintService;

    public ComplaintController(ComplaintService complaintService) {
        this.complaintService = complaintService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasAuthority('complaint:create')")
    public ComplaintResponses.Created create(@Valid @RequestBody ComplaintRequests.Create request) {
        return complaintService.create(request);
    }

    /**
     * The complaint ledger: filtered, sorted, paged (requirement 3.1.1).
     *
     * The parameters are taken one by one rather than bound to a record, so the
     * contract is visible here and does not lean on constructor-name reflection.
     * {@code scope} is "mine" (default) or "all".
     */
    @GetMapping
    @PreAuthorize(MAY_VIEW)
    public ComplaintResponses.LedgerPage list(
            @RequestParam(required = false) String scope,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String priority,
            @RequestParam(required = false) String customer,
            @RequestParam(required = false) String complaintType,
            @RequestParam(required = false) String owner,
            @RequestParam(required = false) String product,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startTo,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate targetFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate targetTo,
            @RequestParam(required = false) Boolean overdue,
            @RequestParam(required = false) Boolean open,
            @RequestParam(required = false) Boolean valid,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort,
            @RequestParam(required = false) String order) {
        return complaintService.listLedger(new ComplaintRequests.LedgerQuery(
                scope, q, status, priority, customer, complaintType, owner, product,
                startFrom, startTo, targetFrom, targetTo, overdue, open, valid,
                page, size, sort, order, null));
    }

    /**
     * The ledger as an .xlsx workbook. Accepts the list's filters again (see
     * {@link #list}) plus {@code ids}: a comma-separated selection, which is what
     * the table sends when rows are ticked. The parameter list is repeated rather
     * than shared so each endpoint reads as a complete contract.
     *
     * The literal path is matched before the {complaintId} template, so "export"
     * does not need to be excluded from complaint ids.
     */
    @GetMapping("/export")
    @PreAuthorize(MAY_VIEW)
    public ResponseEntity<byte[]> export(
            @RequestParam(required = false) String scope,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String priority,
            @RequestParam(required = false) String customer,
            @RequestParam(required = false) String complaintType,
            @RequestParam(required = false) String owner,
            @RequestParam(required = false) String product,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startTo,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate targetFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate targetTo,
            @RequestParam(required = false) Boolean overdue,
            @RequestParam(required = false) Boolean open,
            @RequestParam(required = false) Boolean valid,
            @RequestParam(required = false) String sort,
            @RequestParam(required = false) String order,
            @RequestParam(required = false) String ids) {
        byte[] workbook = complaintService.exportLedger(new ComplaintRequests.LedgerQuery(
                scope, q, status, priority, customer, complaintType, owner, product,
                startFrom, startTo, targetFrom, targetTo, overdue, open, valid,
                null, null, sort, order, splitIds(ids)));

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(XLSX_MIME))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename("complaint-ledger.xlsx", StandardCharsets.UTF_8)
                                .build()
                                .toString())
                .body(workbook);
    }

    /** "A,B" -> [A, B]; blank -> null, so the filter is skipped entirely. */
    private static List<String> splitIds(String ids) {
        if (ids == null || ids.isBlank()) {
            return null;
        }
        return Arrays.stream(ids.split(","))
                .map(String::trim)
                .filter(id -> !id.isEmpty())
                .toList();
    }

    @GetMapping("/{complaintId}")
    @PreAuthorize(MAY_VIEW)
    public ComplaintResponses.Detail detail(@PathVariable String complaintId) {
        return complaintService.getDetail(complaintId);
    }

    /**
     * Target-date rule per priority, for the wizard's live date preview. The
     * literal path is matched before the {complaintId} template, so there is no
     * ambiguity with a complaint actually named "priority-rules".
     */
    @GetMapping("/priority-rules")
    @PreAuthorize(MAY_VIEW)
    public List<ComplaintResponses.PriorityRule> priorityRules() {
        return complaintService.priorityRules();
    }
}
