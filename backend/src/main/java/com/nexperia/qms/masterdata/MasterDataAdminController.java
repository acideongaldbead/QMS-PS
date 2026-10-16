package com.nexperia.qms.masterdata;

import com.nexperia.qms.masterdata.dto.MasterDataAdminDtos;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Maintaining the platform's own reference data (PS-109 / PS-036).
 *
 * A {@code /manage} sub-namespace, like announcements, so the read endpoints that
 * every picker depends on stay exactly as they were.
 *
 * Reads accept {@code admin.all} as well as {@code masterdata:manage}: the /admin
 * route is gated on {@code admin.all}, and a role could hold it without holding
 * {@code masterdata:manage} -- that user should still see the data rather than a
 * 403 on a screen they were allowed into. Writes stay on {@code masterdata:manage}.
 *
 * Reusing the existing permission code is deliberate: adding one would have meant
 * a migration to grant it to the administrator (V3 granted a snapshot) and an
 * update to the assertion that counts permissions.
 */
@RestController
@RequestMapping("/api/master-data/manage")
public class MasterDataAdminController {

    private static final String MAY_READ = "hasAnyAuthority('admin.all','masterdata:manage')";
    private static final String MAY_MANAGE = "hasAuthority('masterdata:manage')";

    private final MasterDataAdminService service;

    public MasterDataAdminController(MasterDataAdminService service) {
        this.service = service;
    }

    // ------------------------------------------------------------- dictionary

    /** The types the screen offers, with their counts and whether they are editable. */
    @GetMapping("/dictionary-types")
    @PreAuthorize(MAY_READ)
    public List<MasterDataAdminDtos.DictionaryType> dictionaryTypes() {
        return service.dictionaryTypes();
    }

    @GetMapping("/dictionary/{mdType}")
    @PreAuthorize(MAY_READ)
    public List<MasterDataAdminDtos.ItemView> items(@PathVariable String mdType) {
        return service.items(mdType);
    }

    @PostMapping("/dictionary/{mdType}")
    @PreAuthorize(MAY_MANAGE)
    public void createItem(@PathVariable String mdType,
                           @Valid @RequestBody MasterDataAdminDtos.DictionaryCreateRequest request) {
        service.createItem(mdType, request);
    }

    @PutMapping("/dictionary/{mdType}/{code}")
    @PreAuthorize(MAY_MANAGE)
    public void updateItem(@PathVariable String mdType, @PathVariable String code,
                           @Valid @RequestBody MasterDataAdminDtos.DictionaryUpdateRequest request) {
        service.updateItem(mdType, code, request);
    }

    @PostMapping("/dictionary/{mdType}/{code}/activate")
    @PreAuthorize(MAY_MANAGE)
    public void activateItem(@PathVariable String mdType, @PathVariable String code) {
        service.setItemActive(mdType, code, true);
    }

    @PostMapping("/dictionary/{mdType}/{code}/deactivate")
    @PreAuthorize(MAY_MANAGE)
    public void deactivateItem(@PathVariable String mdType, @PathVariable String code) {
        service.setItemActive(mdType, code, false);
    }

    @DeleteMapping("/dictionary/{mdType}/{code}")
    @PreAuthorize(MAY_MANAGE)
    public void deleteItem(@PathVariable String mdType, @PathVariable String code) {
        service.deleteItem(mdType, code);
    }

    // ----------------------------------------------------------- failure type

    /** The whole tree, inactive nodes included, so they can be switched back on. */
    @GetMapping("/failure-types/tree")
    @PreAuthorize(MAY_READ)
    public List<MasterDataAdminDtos.FailureTypeNode> failureTypeTree() {
        return service.failureTypeTree();
    }

    @PostMapping("/failure-types")
    @PreAuthorize(MAY_MANAGE)
    public void createFailureType(@Valid @RequestBody MasterDataAdminDtos.FailureTypeCreateRequest request) {
        service.createFailureType(request);
    }

    @PutMapping("/failure-types/{code}")
    @PreAuthorize(MAY_MANAGE)
    public void renameFailureType(@PathVariable String code,
                                  @Valid @RequestBody MasterDataAdminDtos.FailureTypeUpdateRequest request) {
        service.renameFailureType(code, request);
    }

    @PostMapping("/failure-types/{code}/activate")
    @PreAuthorize(MAY_MANAGE)
    public void activateFailureType(@PathVariable String code) {
        service.setFailureTypeActive(code, true);
    }

    @PostMapping("/failure-types/{code}/deactivate")
    @PreAuthorize(MAY_MANAGE)
    public void deactivateFailureType(@PathVariable String code) {
        service.setFailureTypeActive(code, false);
    }

    @DeleteMapping("/failure-types/{code}")
    @PreAuthorize(MAY_MANAGE)
    public void deleteFailureType(@PathVariable String code) {
        service.deleteFailureType(code);
    }
}
