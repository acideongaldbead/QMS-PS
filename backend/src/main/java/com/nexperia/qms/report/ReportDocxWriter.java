package com.nexperia.qms.report;

import com.nexperia.qms.actions.dto.ActionDtos;
import com.nexperia.qms.complaint.dto.ComplaintLabels;
import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import com.nexperia.qms.containment.dto.ContainmentDtos;
import com.nexperia.qms.report.dto.ReportDtos;
import com.nexperia.qms.rootcause.dto.RootCauseDtos;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xwpf.usermodel.XWPFParagraph;
import org.apache.poi.xwpf.usermodel.XWPFRun;
import org.apache.poi.xwpf.usermodel.XWPFTable;
import org.apache.poi.xwpf.usermodel.XWPFTableCell;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Renders an assembled 8D report to a .docx, following the XTE-0071 section order
 * (requirement 3.9).
 *
 * Built in code rather than from a template file: the agreed XTE-0071.docx was not
 * handed over with the requirements, only its extracted text, so a template-driven
 * render would guess at a layout we do not have. The section order and fixed labels
 * below are taken from that text; if the real template arrives, this writer is the
 * single place to swap.
 */
@Component
public class ReportDocxWriter {

    public byte[] write(ReportDtos.ReportContent content) {
        try (XWPFDocument doc = new XWPFDocument();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            header(doc, content);
            complaintInformation(doc, content);
            customerFailure(doc, content);
            sampleTable(doc, content);
            team(doc, content);
            d2Problem(doc, content);
            d3Containment(doc, content);
            d4RootCause(doc, content);
            d5d6CorrectiveActions(doc, content);
            d7Systemic(doc, content);
            d8Recognition(doc, content);
            signOff(doc, content);
            doc.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("生成 8D 报告文档失败：" + e.getMessage(), e);
        }
    }

    // ------------------------------------------------------------------ sections

    private void header(XWPFDocument doc, ReportDtos.ReportContent content) {
        ReportDtos.ReportView r = content.report();
        ComplaintResponses.Detail c = content.complaint();
        title(doc, "TECHNICAL REPORT / 8D Problem Report");
        line(doc, "Nexperia Reference Number: " + nz(c.complaintId())
                + "    8D case nr: " + nz(r.reportId())
                + "    Report version: " + nz(r.versionNo()));
        line(doc, "Report type: " + nz(r.reportTypeName()) + "    Template: " + nz(r.templateCode()));
        line(doc, "Opened: " + date(c.startDate()) + "    Closed: " + date(r.reportCloseDate()));
    }

    private void complaintInformation(XWPFDocument doc, ReportDtos.ReportContent content) {
        ComplaintResponses.Detail c = content.complaint();
        ComplaintLabels l = c.labels();
        ComplaintRequests.FailureDescription fd = c.failureDescription();
        ComplaintRequests.QualityPartner qp = c.qualityPartner();

        heading(doc, "Complaint information");
        List<List<String>> rows = new ArrayList<>();
        rows.add(List.of("Customer", nz(l == null ? null : l.customerName())));
        rows.add(List.of("Product Type", nz(l == null ? null : l.productDescription())));
        rows.add(List.of("End Customer", nz(qp == null ? null : qp.endCustomer())));
        rows.add(List.of("Fail Qty", qty(fd == null ? null : fd.quantityFailing())
                + " " + nz(fd == null ? null : fd.quantityFailingUom())));
        rows.add(List.of("Returned Qty", qty(fd == null ? null : fd.qualityReturned())
                + " " + nz(fd == null ? null : fd.qualityReturnedUom())));
        rows.add(List.of("Customer Ref. No.", nz(c.customerReferenceId())));
        rows.add(List.of("Registration Date", date(c.createdAt() == null ? null : c.createdAt().toLocalDate())));
        rows.add(List.of("Start Date", date(c.startDate())));
        rows.add(List.of("Customer contact", nz(l == null ? null : l.contactName())
                + " (" + nz(l == null ? null : l.contactEmail()) + ")"));
        rows.add(List.of("Location of Failure", nz(l == null ? null : l.failureLocationName())));
        rows.add(List.of("Report Date", date(LocalDate.now())));
        table(doc, List.of("Field", "Value"), rows);
    }

    private void customerFailure(XWPFDocument doc, ReportDtos.ReportContent content) {
        ComplaintRequests.FailureDescription fd = content.complaint().failureDescription();
        heading(doc, "Customer failure description");
        line(doc, firstNonBlank(fd == null ? null : fd.d0SymptomsDescription(),
                fd == null ? null : fd.customerFailureDescription()));
    }

    private void sampleTable(XWPFDocument doc, ReportDtos.ReportContent content) {
        heading(doc, "Detailed sample information");
        List<List<String>> rows = new ArrayList<>();
        for (ComplaintResponses.SampleDetail s : content.complaint().samples()) {
            ComplaintRequests.Sample v = s.value();
            rows.add(List.of(nz(s.sampleId()), qty(v.sampleQuantity()) + " " + nz(v.uom()),
                    Boolean.TRUE.equals(v.rejectConfirmed()) ? "Yes" : "No",
                    nz(v.failureTypeL3Code()), nz(v.conclusion())));
        }
        table(doc, List.of("Sample No.", "Qty", "Reject Confirmed", "Failure Type", "Conclusion"), rows);
    }

    private void team(XWPFDocument doc, ReportDtos.ReportContent content) {
        title(doc, "D1  MULTIDISCIPLINARY team");
        List<List<String>> rows = new ArrayList<>();
        for (ReportDtos.TeamMemberView m : content.team()) {
            rows.add(List.of(nz(m.functionName()), nz(m.memberName()), nz(m.jobTitle())));
        }
        table(doc, List.of("Function", "Name", "Job Title"), rows);
    }

    private void d2Problem(XWPFDocument doc, ReportDtos.ReportContent content) {
        ComplaintResponses.Detail c = content.complaint();
        ComplaintRequests.FailureDescription fd = c.failureDescription();
        title(doc, "D2  PROBLEM DESCRIPTION");
        line(doc, firstNonBlank(fd == null ? null : fd.customerFailureDescription(),
                fd == null ? null : fd.d0SymptomsDescription()));
        line(doc, "Validity: " + (c.isValid() == null ? "未判定" : (c.isValid() ? "有效" : "无效")));
        if (fd != null && notBlank(fd.analysisConclusion())) {
            line(doc, "Analysis conclusion: " + fd.analysisConclusion());
        }
    }

    private void d3Containment(XWPFDocument doc, ReportDtos.ReportContent content) {
        ContainmentDtos.ContainmentSummary box = content.containment();
        title(doc, "D3  CONTAINMENT ACTIONS (Interim Actions)");
        if (box == null || box.required() == null) {
            line(doc, "尚未给出遏制判断。");
            return;
        }
        line(doc, "Containment required: " + (box.required() ? "Yes" : "No")
                + (notBlank(box.decisionNote()) ? " —— " + box.decisionNote() : ""));
        List<List<String>> rows = new ArrayList<>();
        for (ContainmentDtos.ActionView a : box.actions()) {
            rows.add(List.of(nz(a.plannedAction()), nz(a.ownerName()),
                    date(a.plannedCompletionDate()), date(a.completedDate()),
                    nz(a.statusName()), nz(a.result())));
        }
        table(doc, List.of("Description", "Action owner", "Planned", "Completed", "Status", "Verification"), rows);
    }

    private void d4RootCause(XWPFDocument doc, ReportDtos.ReportContent content) {
        title(doc, "D4  ROOT CAUSE");
        List<RootCauseDtos.RootCauseView> roots = content.rootCauses();
        if (roots.isEmpty()) {
            line(doc, "尚未登记根因。");
            return;
        }
        for (RootCauseDtos.RootCauseView rc : roots) {
            line(doc, "• " + nz(rc.rootCauseDesc()));
            if (notBlank(rc.riskAssessment())) {
                line(doc, "  Risk assessment: " + rc.riskAssessment());
            }
            line(doc, "  Analyses: 3x5Why ×" + rc.whyVersionCount()
                    + ", Fishbone ×" + rc.fishboneVersionCount());
        }
    }

    private void d5d6CorrectiveActions(XWPFDocument doc, ReportDtos.ReportContent content) {
        List<ActionDtos.CorrectiveActionView> actions = content.correctiveActions();
        title(doc, "D5 / D6  CORRECTIVE ACTIONS");
        if (actions.isEmpty()) {
            line(doc, "尚未制定纠正措施。");
            return;
        }
        List<List<String>> rows = new ArrayList<>();
        for (ActionDtos.CorrectiveActionView a : actions) {
            rows.add(List.of(nz(a.correctiveActionId()), nz(a.plannedActionDesc()), nz(a.ownerName()),
                    date(a.targetDate()), nz(a.statusName()), effectiveness(a.isEffective())));
        }
        table(doc, List.of("No.", "Actions", "Owner", "Target Date", "Status", "Verification"), rows);
    }

    private void d7Systemic(XWPFDocument doc, ReportDtos.ReportContent content) {
        title(doc, "D7  IMPLEMENTED SYSTEMIC CORRECTIVE ACTION");
        List<ActionDtos.PreventionView> files = content.preventionFiles();
        if (files.isEmpty()) {
            line(doc, "尚未登记预防文件更新。");
        } else {
            List<List<String>> rows = new ArrayList<>();
            for (ActionDtos.PreventionView f : files) {
                rows.add(List.of(nz(f.fileTypeName()), nz(f.controlProgram()), nz(f.referenceNumber()), nz(f.statusName())));
            }
            table(doc, List.of("Document", "Control program", "Reference no.", "Status"), rows);
        }

        // XTE-0071 keeps Read-across as its own block after D7 (the sample report
        // omits it entirely). The business confirmed on 2026-10-14 that the system
        // is not to fill this block for now, so printing the template's own prompt
        // is the intended end state, not a gap waiting to be closed.
        title(doc, "Read-across");
        line(doc, "Analyze similar processes / systems / practices and implement the systemic corrective action where applicable.");
        line(doc, "—");
    }

    /**
     * D8 as XTE-0071 defines it: the team-recognition block. The sample report
     * replaced this with its sign-off page, which is why the two disagree; the
     * template was chosen as the reference. Like Read-across, the recognition text
     * is deliberately not filled by the system (business decision, 2026-10-14), so
     * the template's own prompt is printed.
     */
    private void d8Recognition(XWPFDocument doc, ReportDtos.ReportContent content) {
        title(doc, "D8  TEAM RECOGNITION");
        line(doc, "Date: " + date(content.report().reportCloseDate()));
        line(doc, "Recognize the collective efforts of the team.");
    }

    /**
     * Who reported, who approved and where it went. The template ends at team
     * recognition; this block is what the sent report leaves behind, so it stays -
     * labelled without a D-number so it cannot be read as the template's D8.
     */
    private void signOff(XWPFDocument doc, ReportDtos.ReportContent content) {
        ReportDtos.ReportView r = content.report();
        ComplaintLabels l = content.complaint().labels();
        title(doc, "SIGN-OFF AND DISTRIBUTION");
        line(doc, "Reported by: " + nz(l == null ? null : l.reportOwnerName()));
        line(doc, "Approved by: " + approvalLine(r));
        line(doc, "Opened / Closed: " + date(r.reportStartDate()) + " / " + date(r.reportCloseDate()));
        List<List<String>> rows = new ArrayList<>();
        for (ReportDtos.DistributionView d : content.distributions()) {
            rows.add(List.of(nz(d.senderName()), nz(d.recipient()), nz(d.ccList()), nz(d.attachmentVersion())));
        }
        table(doc, List.of("Sent by", "Recipient", "CC", "Version"), rows);
    }

    private static String approvalLine(ReportDtos.ReportView r) {
        if (r.approval() == null || r.approval().approverName() == null) {
            return nz(r.approvalStatusName());
        }
        return r.approval().approverName() + "（" + nz(r.approvalStatusName()) + "）";
    }

    // ------------------------------------------------------------------ helpers

    private void title(XWPFDocument doc, String text) {
        XWPFParagraph p = doc.createParagraph();
        p.setSpacingBefore(200);
        XWPFRun run = p.createRun();
        run.setBold(true);
        run.setFontSize(13);
        run.setText(text);
    }

    private void heading(XWPFDocument doc, String text) {
        XWPFParagraph p = doc.createParagraph();
        XWPFRun run = p.createRun();
        run.setBold(true);
        run.setText(text);
    }

    private void line(XWPFDocument doc, String text) {
        doc.createParagraph().createRun().setText(text);
    }

    private void table(XWPFDocument doc, List<String> headers, List<List<String>> rows) {
        XWPFTable table = doc.createTable(rows.size() + 1, headers.size());
        for (int j = 0; j < headers.size(); j++) {
            cell(table.getRow(0).getCell(j), headers.get(j), true);
        }
        for (int i = 0; i < rows.size(); i++) {
            List<String> row = rows.get(i);
            for (int j = 0; j < headers.size(); j++) {
                cell(table.getRow(i + 1).getCell(j), j < row.size() ? row.get(j) : "", false);
            }
        }
        doc.createParagraph();
    }

    private void cell(XWPFTableCell cell, String text, boolean bold) {
        cell.removeParagraph(0);
        XWPFRun run = cell.addParagraph().createRun();
        run.setBold(bold);
        run.setText(nz(text));
    }

    private static String effectiveness(Boolean value) {
        if (value == null) {
            return "未判定";
        }
        return value ? "有效" : "无效";
    }

    private static String date(LocalDate d) {
        return d == null ? "" : d.toString();
    }

    private static String qty(java.math.BigDecimal v) {
        return v == null ? "" : v.stripTrailingZeros().toPlainString();
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    private static String nz(String s) {
        return s == null ? "" : s;
    }

    private static String firstNonBlank(String a, String b) {
        return notBlank(a) ? a : nz(b);
    }
}
