package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
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
import java.util.List;

/**
 * Renders the permission matrix as an .xlsx workbook (requirement 3.12,
 * PS-113 AC2: the matrix must be exportable for the record).
 *
 * One line per role x permission pair rather than a wide grid: the pair list
 * stays readable however many roles and permissions there are, and it can be
 * filtered or pivoted afterwards. Built from code, like the ledger and 8D
 * exports, so it cannot drift from what the screen shows.
 */
@Component
public class MatrixExcelWriter {

    private static final String SHEET_NAME = "Permission Matrix";

    private static final String[] HEADERS = {
            "角色", "角色类型", "模块", "权限码", "权限名称", "权限级别", "已勾选"
    };

    private static final int[] WIDTHS = {24, 10, 14, 26, 24, 12, 9};

    public byte[] toWorkbook(List<AdminDtos.MatrixCell> cells) {
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
            for (AdminDtos.MatrixCell cell : cells) {
                Row line = sheet.createRow(rowIndex++);
                int column = 0;
                line.createCell(column++).setCellValue(text(cell.roleName()));
                line.createCell(column++).setCellValue(roleType(cell.roleType()));
                line.createCell(column++).setCellValue(text(cell.moduleCode()));
                line.createCell(column++).setCellValue(text(cell.permissionCode()));
                line.createCell(column++).setCellValue(text(cell.permissionName()));
                line.createCell(column++).setCellValue(permissionLevel(cell.permissionLevel()));
                line.createCell(column).setCellValue(cell.granted() ? "是" : "");
            }

            workbook.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to build the permission matrix workbook", e);
        }
    }

    private CellStyle headerStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        return style;
    }

    /** The stored values are the codes; the sheet is read by people. */
    private static String roleType(String value) {
        return switch (value == null ? "" : value) {
            case "PRESET" -> "预设";
            case "CUSTOM" -> "自定义";
            default -> text(value);
        };
    }

    private static String permissionLevel(String value) {
        return switch (value == null ? "" : value) {
            case "SYSTEM" -> "系统级";
            case "MODULE" -> "模块级";
            case "BUTTON" -> "功能按钮级";
            case "ROW" -> "数据行级";
            default -> text(value);
        };
    }

    private static String text(String value) {
        return value == null ? "" : value;
    }
}
