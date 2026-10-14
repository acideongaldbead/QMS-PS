package com.nexperia.qms.report;

import com.nexperia.qms.actions.dto.ActionDtos;
import com.nexperia.qms.complaint.dto.ComplaintLabels;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import com.nexperia.qms.containment.dto.ContainmentDtos;
import com.nexperia.qms.report.dto.ReportDtos;
import com.nexperia.qms.rootcause.dto.RootCauseDtos;
import com.nexperia.qms.verification.dto.VerificationDtos;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDFont;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Renders an assembled 8D report to a PDF, in the same section order as
 * {@link ReportDocxWriter} (XTE-0071).
 *
 * The layout is deliberately plainer than the Word file: paragraphs, wrapped and
 * paginated, with the table-shaped content written as "cell | cell" lines. Word
 * stays the editable, template-shaped artefact; the PDF is the read-only copy.
 * If the official template arrives, both writers change together.
 *
 * A Chinese font is embedded, because PDF's built-in fonts cannot render the
 * report's Chinese content at all (they would emit blanks, not squares). The
 * font is taken from {@code qms.report.pdf-font}, falling back to the Windows
 * simplified-Chinese fonts; a missing font is reported rather than silently
 * producing an unreadable file.
 */
@Component
public class ReportPdfWriter {

    /** Windows ships at least one of these on a simplified-Chinese install. */
    private static final List<String> FALLBACK_FONTS = List.of(
            "C:/Windows/Fonts/simhei.ttf",
            "C:/Windows/Fonts/msyh.ttf",
            "C:/Windows/Fonts/Deng.ttf");

    private final String configuredFont;

    public ReportPdfWriter(@Value("${qms.report.pdf-font:}") String configuredFont) {
        this.configuredFont = configuredFont;
    }

    public byte[] write(ReportDtos.ReportContent content) {
        try (PDDocument document = new PDDocument();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Canvas canvas = new Canvas(document, loadFont(document));
            try {
                render(canvas, content);
            } finally {
                canvas.close();
            }
            document.save(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("生成 8D 报告 PDF 失败：" + e.getMessage(), e);
        }
    }

    private PDFont loadFont(PDDocument document) throws IOException {
        List<String> candidates = new ArrayList<>();
        if (configuredFont != null && !configuredFont.isBlank()) {
            candidates.add(configuredFont);
        }
        candidates.addAll(FALLBACK_FONTS);

        for (String path : candidates) {
            File file = new File(path);
            if (!file.isFile()) {
                continue;
            }
            if (path.toLowerCase().endsWith(".ttc")) {
                throw new IllegalStateException("qms.report.pdf-font 需指向单个 .ttf 字体，不支持字体集合："
                        + path + "（可改用 " + FALLBACK_FONTS.get(0) + "）");
            }
            return PDType0Font.load(document, file);
        }
        throw new IllegalStateException("找不到可用的中文字体，无法生成 PDF。请设置 qms.report.pdf-font "
                + "指向一个 .ttf 字体（已尝试：" + String.join("、", candidates) + "）");
    }

    // ------------------------------------------------------------------ content

    private void render(Canvas canvas, ReportDtos.ReportContent content) throws IOException {
        ReportDtos.ReportView report = content.report();
        ComplaintResponses.Detail complaint = content.complaint();
        ComplaintLabels labels = complaint.labels();

        canvas.title("TECHNICAL REPORT / 8D Problem Report");
        canvas.body("Nexperia Reference Number: " + nz(complaint.complaintId())
                + "    8D case nr: " + nz(report.reportId())
                + "    Report version: " + nz(report.versionNo()));
        canvas.body("Report type: " + nz(report.reportTypeName())
                + "    Template: " + nz(report.templateCode())
                + "    Approval: " + nz(report.approvalStatusName()));
        canvas.body("Customer: " + nz(labels == null ? null : labels.customerName())
                + "    Product: " + nz(labels == null ? null : labels.productDescription()));
        canvas.body("Opened: " + date(complaint.startDate())
                + "    Target: " + date(complaint.targetDate())
                + "    Closed: " + date(report.reportCloseDate()));

        canvas.heading("D1 MULTIDISCIPLINARY team");
        if (content.team().isEmpty()) {
            canvas.body("—");
        }
        for (ReportDtos.TeamMemberView member : content.team()) {
            canvas.body(nz(member.functionName()) + ": " + nz(member.memberName())
                    + " (" + nz(member.jobTitle()) + ")");
        }

        canvas.heading("D2 PROBLEM DESCRIPTION");
        if (complaint.failureDescription() != null) {
            canvas.body("Customer failure: " + nz(complaint.failureDescription().customerFailureDescription()));
            canvas.body("Symptoms: " + nz(complaint.failureDescription().d0SymptomsDescription()));
            canvas.body("Customer failure mode: " + nz(labels == null ? null : labels.customerFailureModeName()));
        }
        canvas.body("Conclusion: " + (complaint.isValid() == null ? "—"
                : (complaint.isValid() ? "complaint valid" : "complaint not valid")));
        for (VerificationDtos.TaskView task : content.verificationTasks()) {
            canvas.body("Task " + nz(task.taskId()) + "    Owner: " + nz(task.taskOwnerName())
                    + "    Status: " + nz(task.taskStatusName())
                    + "    Due: " + date(task.targetCompletionDate())
                    + "    Results: " + task.resultCount());
        }

        canvas.heading("D3 CONTAINMENT ACTIONS");
        ContainmentDtos.ContainmentSummary containment = content.containment();
        if (containment == null || containment.required() == null) {
            canvas.body("—");
        } else if (!containment.required()) {
            canvas.body("Containment not required. " + nz(containment.decisionNote()));
        } else {
            canvas.body("Containment required. " + nz(containment.decisionNote()));
            for (ContainmentDtos.ActionView action : containment.actions()) {
                canvas.body("· " + nz(action.plannedAction())
                        + "    Responsibility: " + nz(action.ownerName())
                        + "    Status: " + nz(action.statusName())
                        + "    Closed: " + date(action.completedDate()));
                if (action.result() != null && !action.result().isBlank()) {
                    canvas.body("  Result: " + action.result());
                }
            }
        }

        canvas.heading("D4 ROOT CAUSE");
        if (content.rootCauses().isEmpty()) {
            canvas.body("—");
        }
        for (RootCauseDtos.RootCauseView root : content.rootCauses()) {
            canvas.body("· " + nz(root.rootCauseSummary()) + "    Status: " + nz(root.statusName())
                    + "    Organisation: " + nz(root.responsibleOrgName()));
            canvas.body("  " + nz(root.rootCauseDesc()));
            if (root.riskAssessment() != null && !root.riskAssessment().isBlank()) {
                canvas.body("  Risk: " + root.riskAssessment());
            }
        }

        canvas.heading("D5/D6 IMPLEMENTED CORRECTIVE ACTIONS");
        if (content.correctiveActions().isEmpty()) {
            canvas.body("—");
        }
        for (ActionDtos.CorrectiveActionView action : content.correctiveActions()) {
            canvas.body("· " + nz(action.plannedActionDesc())
                    + "    Owner: " + nz(action.ownerName())
                    + "    Target: " + date(action.targetDate())
                    + "    Status: " + nz(action.statusName()));
            if (action.verificationResult() != null && !action.verificationResult().isBlank()) {
                canvas.body("  Verified by " + nz(action.verifiedByName()) + " on "
                        + date(action.actualCompletionDate()) + ": " + action.verificationResult());
            }
        }

        canvas.heading("D7 IMPLEMENTED SYSTEMIC CORRECTIVE ACTION");
        if (content.preventionFiles().isEmpty()) {
            canvas.body("—");
        }
        for (ActionDtos.PreventionView file : content.preventionFiles()) {
            canvas.body("· " + nz(file.fileTypeName())
                    + "    Control program: " + nz(file.controlProgram())
                    + "    Reference: " + nz(file.referenceNumber())
                    + "    Status: " + nz(file.statusName()));
        }

        // XTE-0071 places Read-across and Team Recognition after D7. The business
        // confirmed on 2026-10-14 that the system is not to fill either block, so
        // printing the template's own prompts is the intended end state.
        canvas.heading("Read-across");
        canvas.body("Analyze similar processes / systems / practices and implement the systemic corrective action where applicable.");
        canvas.body("—");

        canvas.heading("D8 TEAM RECOGNITION");
        canvas.body("Date: " + date(report.reportCloseDate()));
        canvas.body("Recognize the collective efforts of the team.");

        canvas.heading("SIGN-OFF AND DISTRIBUTION");
        canvas.body("Reported by: " + nz(labels == null ? null : labels.reportOwnerName())
                + "    Approved by: " + nz(report.approvalStatusName())
                + (report.approval() == null ? "" : "    Approver: " + nz(report.approval().approverName())));
        if (content.distributions().isEmpty()) {
            canvas.body("Not sent to the customer yet.");
        }
        for (ReportDtos.DistributionView entry : content.distributions()) {
            canvas.body("Sent to " + nz(entry.recipient())
                    + (entry.ccList() == null || entry.ccList().isBlank() ? "" : " (cc " + entry.ccList() + ")")
                    + "    Version: " + nz(entry.attachmentVersion()));
        }
    }

    // ------------------------------------------------------------------ layout

    /**
     * A minimal page writer: one column of wrapped paragraphs, moving to a new
     * page when the current one runs out. PDFBox has no layout engine, so the
     * wrapping and the page break are done here.
     */
    private static final class Canvas {

        private static final float MARGIN = 42f;
        private static final float TEXT_WIDTH = PDRectangle.A4.getWidth() - 2 * MARGIN;

        private final PDDocument document;
        private final PDFont font;
        /** Characters this font cannot draw; substituted rather than throwing. */
        private final Set<Character> unsupported = new HashSet<>();

        private PDPageContentStream stream;
        private float y;

        Canvas(PDDocument document, PDFont font) throws IOException {
            this.document = document;
            this.font = font;
            newPage();
        }

        void title(String text) throws IOException {
            paragraph(text, 15f);
        }

        void heading(String text) throws IOException {
            y -= 6;
            paragraph(text, 11f);
        }

        void body(String text) throws IOException {
            paragraph(text, 9f);
        }

        private void paragraph(String value, float size) throws IOException {
            for (String line : wrap(value, size)) {
                if (y < MARGIN + size) {
                    newPage();
                }
                stream.beginText();
                stream.setFont(font, size);
                stream.newLineAtOffset(MARGIN, y);
                stream.showText(line);
                stream.endText();
                y -= size + 4f;
            }
        }

        private List<String> wrap(String value, float size) throws IOException {
            List<String> lines = new ArrayList<>();
            if (value == null || value.isBlank()) {
                lines.add("");
                return lines;
            }
            for (String paragraph : value.split("\r?\n")) {
                StringBuilder line = new StringBuilder();
                for (int i = 0; i < paragraph.length(); i++) {
                    char ch = renderable(paragraph.charAt(i));
                    if (width(line.toString() + ch, size) > TEXT_WIDTH && line.length() > 0) {
                        lines.add(line.toString());
                        line.setLength(0);
                    }
                    line.append(ch);
                }
                lines.add(line.toString());
            }
            return lines;
        }

        private char renderable(char ch) throws IOException {
            if (ch == '\t') {
                return ' ';
            }
            if (unsupported.contains(ch)) {
                return '?';
            }
            try {
                font.getStringWidth(String.valueOf(ch));
                return ch;
            } catch (IllegalArgumentException e) {
                // The font has no glyph for it; show something instead of failing.
                unsupported.add(ch);
                return '?';
            }
        }

        private float width(String text, float size) throws IOException {
            return font.getStringWidth(text) / 1000f * size;
        }

        private void newPage() throws IOException {
            if (stream != null) {
                stream.close();
            }
            PDPage page = new PDPage(PDRectangle.A4);
            document.addPage(page);
            stream = new PDPageContentStream(document, page);
            y = PDRectangle.A4.getHeight() - MARGIN;
        }

        void close() throws IOException {
            if (stream != null) {
                stream.close();
                stream = null;
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    private static String nz(String value) {
        return value == null || value.isBlank() ? "—" : value;
    }

    private static String date(LocalDate value) {
        return value == null ? "—" : value.toString();
    }
}
