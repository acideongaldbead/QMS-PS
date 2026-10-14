package com.nexperia.qms.complaint;

import com.nexperia.qms.complaint.dto.ComplaintResponses;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Renders ledger rows as an .xlsx workbook.
 *
 * The same call as the 8D report's .docx: the file is produced by code (POI is
 * already a dependency) rather than from a checked-in template, so the export
 * cannot drift from the on-screen columns.
 */
@Component
public class LedgerExcelWriter {

    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    private static final String SHEET_NAME = "Complaint Ledger";

    /** The ledger's list columns, in order, plus the overdue count. */
    private static final String[] HEADERS = {
            "流程ID", "状态", "8D 阶段", "优先级", "质量合作伙伴", "产品类型",
            "开始日期", "目标日期", "关闭日期", "处理天数", "负责人", "客户参考ID", "超期天数"
    };

    /** Column widths in characters; long text columns get more room. */
    private static final int[] WIDTHS = {
            16, 14, 10, 12, 34, 44, 13, 13, 13, 11, 12, 24, 11
    };

    public byte[] toWorkbook(List<ComplaintResponses.LedgerRow> rows) {
        try (Workbook workbook = new XSSFWorkbook();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {

            Sheet sheet = workbook.createSheet(SHEET_NAME);
            CellStyle headerStyle = headerStyle(workbook);

            Row header = sheet.createRow(0);
            for (int i = 0; i < HEADERS.length; i++) {
                Cell cell = header.createCell(i);
                cell.setCellValue(HEADERS[i]);
                cell.setCellStyle(headerStyle);
                sheet.setColumnWidth(i, WIDTHS[i] * 256);
            }

            int rowIndex = 1;
            for (ComplaintResponses.LedgerRow row : rows) {
                Row line = sheet.createRow(rowIndex++);
                int column = 0;
                line.createCell(column++).setCellValue(text(row.complaintId()));
                line.createCell(column++).setCellValue(text(row.statusName()));
                line.createCell(column++).setCellValue(text(row.currentStage()));
                line.createCell(column++).setCellValue(text(row.priorityName()));
                line.createCell(column++).setCellValue(text(row.customerName()));
                line.createCell(column++).setCellValue(text(row.productTypeName()));
                line.createCell(column++).setCellValue(date(row.startDate()));
                line.createCell(column++).setCellValue(date(row.targetDate()));
                line.createCell(column++).setCellValue(date(row.closeDate()));
                line.createCell(column++).setCellValue(dayCount(row.processingDays()));
                line.createCell(column++).setCellValue(text(row.ownerName()));
                line.createCell(column++).setCellValue(text(row.customerReferenceId()));
                line.createCell(column).setCellValue(row.overdueDays());
            }

            workbook.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to build the complaint ledger workbook", e);
        }
    }

    private CellStyle headerStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        return style;
    }

    private static String text(String value) {
        return value == null ? "" : value;
    }

    private static String date(LocalDate value) {
        return value == null ? "" : value.format(DATE);
    }

    private static String dayCount(Integer value) {
        return value == null ? "" : String.valueOf(value);
    }
}
