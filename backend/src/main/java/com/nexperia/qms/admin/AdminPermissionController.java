package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * The permission vocabulary and the matrix export (requirement 3.12, PS-113).
 *
 * Permissions are defined by the migrations, not by the UI: the screen assigns
 * them to roles, it does not invent them. So there is no write endpoint here.
 */
@RestController
@RequestMapping("/api/admin/permissions")
public class AdminPermissionController {

    private static final String MAY_READ = "hasAnyAuthority('admin.all','rbac:manage')";
    private static final String XLSX_MIME =
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    private final AdminRoleService adminRoleService;

    public AdminPermissionController(AdminRoleService adminRoleService) {
        this.adminRoleService = adminRoleService;
    }

    @GetMapping
    @PreAuthorize(MAY_READ)
    public List<AdminDtos.PermissionView> list() {
        return adminRoleService.permissions();
    }

    /** PS-113 AC2: the whole matrix, one line per role x permission. */
    @GetMapping("/matrix/export")
    @PreAuthorize(MAY_READ)
    public ResponseEntity<byte[]> exportMatrix() {
        byte[] workbook = adminRoleService.exportMatrix();
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(XLSX_MIME))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename("permission-matrix.xlsx", StandardCharsets.UTF_8)
                                .build()
                                .toString())
                .body(workbook);
    }
}
