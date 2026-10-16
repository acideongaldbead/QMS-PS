package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * User administration (requirement 3.12).
 *
 * Reads accept {@code admin.all} as well as {@code rbac:manage}: the /admin route
 * is gated on {@code admin.all}, and a role could be built that holds it without
 * holding {@code rbac:manage} -- that user should still see the data on the screen
 * they are allowed into. Writes stay on {@code rbac:manage} alone.
 *
 * No new permission code is introduced; reuse is what keeps the permission total
 * (and the assertions that count it) unchanged.
 */
@RestController
@RequestMapping("/api/admin/users")
public class AdminUserController {

    private static final String MAY_READ = "hasAnyAuthority('admin.all','rbac:manage')";
    private static final String MAY_MANAGE = "hasAuthority('rbac:manage')";

    private final AdminUserService adminUserService;

    public AdminUserController(AdminUserService adminUserService) {
        this.adminUserService = adminUserService;
    }

    @GetMapping
    @PreAuthorize(MAY_READ)
    public List<AdminDtos.UserView> list() {
        return adminUserService.list();
    }

    @PutMapping("/{employeeId}/roles")
    @PreAuthorize(MAY_MANAGE)
    public void assignRoles(@PathVariable String employeeId,
                            @Valid @RequestBody AdminDtos.AssignRolesRequest request) {
        adminUserService.assignRoles(employeeId, request);
    }

    @PostMapping("/{employeeId}/account/activate")
    @PreAuthorize(MAY_MANAGE)
    public void activateAccount(@PathVariable String employeeId) {
        adminUserService.setAccountActive(employeeId, true);
    }

    @PostMapping("/{employeeId}/account/deactivate")
    @PreAuthorize(MAY_MANAGE)
    public void deactivateAccount(@PathVariable String employeeId) {
        adminUserService.setAccountActive(employeeId, false);
    }

    @PostMapping("/{employeeId}/password/reset")
    @PreAuthorize(MAY_MANAGE)
    public void resetPassword(@PathVariable String employeeId,
                              @Valid @RequestBody AdminDtos.ResetPasswordRequest request) {
        adminUserService.resetPassword(employeeId, request);
    }

    @PostMapping("/{employeeId}/unlock")
    @PreAuthorize(MAY_MANAGE)
    public void unlock(@PathVariable String employeeId) {
        adminUserService.unlock(employeeId);
    }
}
