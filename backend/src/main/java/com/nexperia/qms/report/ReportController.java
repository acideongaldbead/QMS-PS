package com.nexperia.qms.report;

import com.nexperia.qms.report.dto.ReportDtos;
import jakarta.validation.Valid;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * D8 reporting and settlement (requirement 3.9).
 *
 * Four capabilities, matching the role matrix: report:view to read, report:generate
 * to assemble a report, report:export to download it as Word, and report:send for
 * the Sales Quality user who sends it to the customer and closes the complaint.
 */
@RestController
@RequestMapping("/api")
public class ReportController {

    private static final String MAY_VIEW = "hasAuthority('report:view')";
    private static final String MAY_GENERATE = "hasAuthority('report:generate')";
    private static final String MAY_EXPORT = "hasAuthority('report:export')";
    private static final String MAY_EDIT = "hasAuthority('report:edit')";
    private static final String MAY_APPROVE = "hasAuthority('report:approve')";
    private static final String MAY_SEND = "hasAuthority('report:send')";

    private static final String DOCX_MIME =
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

    private final ReportService reportService;

    public ReportController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping("/complaints/{complaintId}/reports")
    @PreAuthorize(MAY_VIEW)
    public List<ReportDtos.ReportView> list(@PathVariable String complaintId) {
        return reportService.list(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/reports")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_GENERATE)
    public ReportDtos.ReportView generate(@PathVariable String complaintId,
                                          @Valid @RequestBody ReportDtos.GenerateRequest request) {
        return reportService.generate(complaintId, request.reportType());
    }

    @GetMapping("/reports/{reportId}")
    @PreAuthorize(MAY_VIEW)
    public ReportDtos.ReportContent view(@PathVariable String reportId) {
        return reportService.view(reportId);
    }

    @GetMapping("/reports/{reportId}/export.docx")
    @PreAuthorize(MAY_EXPORT)
    public ResponseEntity<byte[]> export(@PathVariable String reportId) {
        byte[] bytes = reportService.exportDocx(reportId);
        String filename = "8D_Report_" + reportId + ".docx";
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(DOCX_MIME))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename(filename, StandardCharsets.UTF_8).build().toString())
                .body(bytes);
    }

    /** The same report as a PDF, for circulating rather than editing. */
    @GetMapping("/reports/{reportId}/export.pdf")
    @PreAuthorize(MAY_EXPORT)
    public ResponseEntity<byte[]> exportPdf(@PathVariable String reportId) {
        byte[] bytes = reportService.exportPdf(reportId);
        String filename = "8D_Report_" + reportId + ".pdf";
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_PDF)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename(filename, StandardCharsets.UTF_8).build().toString())
                .body(bytes);
    }

    @PostMapping("/reports/{reportId}/send")
    @PreAuthorize(MAY_SEND)
    public ReportDtos.SendResult send(@PathVariable String reportId,
                                      @Valid @RequestBody ReportDtos.SendRequest request) {
        return reportService.send(reportId, request);
    }

    /**
     * Who may approve reports: the submitter picks one of them. Separate from the
     * approval call so the dialog does not need the whole role matrix.
     */
    @GetMapping("/reports/approvers")
    @PreAuthorize(MAY_VIEW)
    public List<ReportDtos.Approver> approvers() {
        return reportService.approvers();
    }

    /** Hands the report to an approver; the send stays blocked until it is approved. */
    @PostMapping("/reports/{reportId}/submit")
    @PreAuthorize(MAY_EDIT)
    public ReportDtos.ReportView submit(@PathVariable String reportId,
                                        @Valid @RequestBody ReportDtos.SubmitRequest request) {
        return reportService.submit(reportId, request);
    }

    /** The approver's decision. Only the named approver may call it. */
    @PostMapping("/reports/{reportId}/approve")
    @PreAuthorize(MAY_APPROVE)
    public ReportDtos.ReportView approve(@PathVariable String reportId,
                                         @Valid @RequestBody ReportDtos.ApprovalRequest request) {
        return reportService.approve(reportId, request);
    }
}
