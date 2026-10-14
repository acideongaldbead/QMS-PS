package com.nexperia.qms.masterdata;

import com.nexperia.qms.masterdata.dto.MasterDataDtos;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Reference data for the pickers and dropdowns. Everything here requires a valid
 * login (the /api/** rule); the raw role and permission lists additionally require
 * rbac:manage, since that is administration, not day-to-day reference data.
 */
@RestController
@RequestMapping("/api/master-data")
public class MasterDataController {

    private final MasterDataService service;

    public MasterDataController(MasterDataService service) {
        this.service = service;
    }

    /** Dictionary lookup by type: complaint_type, priority, failure_location, sub_segment,
     *  product_type, packing_type, failure_mode, file_type, responsible_org. */
    @GetMapping("/dictionary/{mdType}")
    public List<MasterDataDtos.Item> dictionary(@PathVariable String mdType) {
        return service.dictionary(mdType);
    }

    @GetMapping("/failure-types/tree")
    public List<MasterDataDtos.FailureType> failureTypeTree() {
        return service.failureTypeTree();
    }

    @GetMapping("/customers")
    public List<MasterDataDtos.Customer> customers(@RequestParam(required = false) String q) {
        return service.customers(q);
    }

    @GetMapping("/customers/{customerCode}/ship-to")
    public List<MasterDataDtos.Option> shipTo(@PathVariable String customerCode) {
        return service.shipTo(customerCode);
    }

    @GetMapping("/customers/{customerCode}/contacts")
    public List<MasterDataDtos.Contact> contacts(@PathVariable String customerCode) {
        return service.contacts(customerCode);
    }

    @GetMapping("/products")
    public List<MasterDataDtos.Product> products(@RequestParam(required = false) String q) {
        return service.products(q);
    }

    @GetMapping("/employees")
    public List<MasterDataDtos.Employee> employees(@RequestParam(required = false) String q) {
        return service.employees(q);
    }

    @GetMapping("/status-codes")
    public List<MasterDataDtos.Status> statusCodes(@RequestParam(required = false) String entity) {
        return service.statusCodes(entity);
    }

    @GetMapping("/roles")
    @PreAuthorize("hasAuthority('rbac:manage')")
    public List<MasterDataDtos.Role> roles() {
        return service.roles();
    }

    @GetMapping("/permissions")
    @PreAuthorize("hasAuthority('rbac:manage')")
    public List<MasterDataDtos.Permission> permissions() {
        return service.permissions();
    }
}
