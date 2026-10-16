package com.nexperia.qms.admin;

import com.nexperia.qms.admin.dto.AdminDtos;
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
 * Role administration (requirement 3.12): the preset roles, the custom ones built
 * from them, and which permissions each carries.
 */
@RestController
@RequestMapping("/api/admin/roles")
public class AdminRoleController {

    private static final String MAY_READ = "hasAnyAuthority('admin.all','rbac:manage')";
    private static final String MAY_MANAGE = "hasAuthority('rbac:manage')";

    private final AdminRoleService adminRoleService;

    public AdminRoleController(AdminRoleService adminRoleService) {
        this.adminRoleService = adminRoleService;
    }

    @GetMapping
    @PreAuthorize(MAY_READ)
    public List<AdminDtos.RoleView> list() {
        return adminRoleService.list();
    }

    @GetMapping("/{roleId}")
    @PreAuthorize(MAY_READ)
    public AdminDtos.RoleView get(@PathVariable long roleId) {
        return adminRoleService.get(roleId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView create(@Valid @RequestBody AdminDtos.SaveRoleRequest request) {
        return adminRoleService.create(request);
    }

    @PutMapping("/{roleId}")
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView rename(@PathVariable long roleId,
                                     @Valid @RequestBody AdminDtos.SaveRoleRequest request) {
        return adminRoleService.rename(roleId, request);
    }

    @DeleteMapping("/{roleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize(MAY_MANAGE)
    public void delete(@PathVariable long roleId) {
        adminRoleService.delete(roleId);
    }

    /** PS-112 AC3: a preset or custom role becomes a new custom role. */
    @PostMapping("/{roleId}/copy")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView copy(@PathVariable long roleId,
                                   @Valid @RequestBody(required = false) AdminDtos.CopyRoleRequest request) {
        return adminRoleService.copy(roleId, request);
    }

    @PostMapping("/{roleId}/activate")
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView activate(@PathVariable long roleId) {
        return adminRoleService.setActive(roleId, true);
    }

    @PostMapping("/{roleId}/deactivate")
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView deactivate(@PathVariable long roleId) {
        return adminRoleService.setActive(roleId, false);
    }

    @PutMapping("/{roleId}/permissions")
    @PreAuthorize(MAY_MANAGE)
    public AdminDtos.RoleView replacePermissions(@PathVariable long roleId,
                                                 @RequestBody AdminDtos.RolePermissionsRequest request) {
        return adminRoleService.replacePermissions(roleId, request);
    }
}
