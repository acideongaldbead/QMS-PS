package com.nexperia.qms.masterdata;

import com.nexperia.qms.masterdata.dto.MasterDataDtos;
import com.nexperia.qms.masterdata.mapper.MasterDataMapper;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class MasterDataService {

    private final MasterDataMapper mapper;

    public MasterDataService(MasterDataMapper mapper) {
        this.mapper = mapper;
    }

    public List<MasterDataDtos.Item> dictionary(String mdType) {
        return mapper.findDictionary(mdType);
    }

    /** Returns the three-level failure type tree the D2 picker cascades through. */
    public List<MasterDataDtos.FailureType> failureTypeTree() {
        List<MasterDataDtos.FailureTypeRow> rows = mapper.findFailureTypeRows();
        Map<Long, List<MasterDataDtos.FailureTypeRow>> byParent = new HashMap<>();
        for (MasterDataDtos.FailureTypeRow row : rows) {
            byParent.computeIfAbsent(row.parentId(), k -> new ArrayList<>()).add(row);
        }
        return byParent.getOrDefault(null, List.of()).stream()
                .map(row -> attachChildren(row, byParent))
                .toList();
    }

    private MasterDataDtos.FailureType attachChildren(
            MasterDataDtos.FailureTypeRow row,
            Map<Long, List<MasterDataDtos.FailureTypeRow>> byParent) {
        List<MasterDataDtos.FailureType> children = byParent.getOrDefault(row.id(), List.of()).stream()
                .map(child -> attachChildren(child, byParent))
                .toList();
        return new MasterDataDtos.FailureType(
                row.id(), row.levelNo(), row.code(), row.name(), row.parentId(), children);
    }

    public List<MasterDataDtos.Customer> customers(String q) {
        return mapper.findCustomers(normalize(q));
    }

    public List<MasterDataDtos.Option> shipTo(String customerCode) {
        return mapper.findShipTo(customerCode);
    }

    public List<MasterDataDtos.Contact> contacts(String customerCode) {
        return mapper.findContacts(customerCode);
    }

    public List<MasterDataDtos.Product> products(String q) {
        return mapper.findProducts(normalize(q));
    }

    public List<MasterDataDtos.Employee> employees(String q) {
        return mapper.findEmployees(normalize(q));
    }

    public List<MasterDataDtos.Status> statusCodes(String entityName) {
        return mapper.findStatusCodes(normalize(entityName));
    }

    public List<MasterDataDtos.Role> roles() {
        return mapper.findRoles();
    }

    public List<MasterDataDtos.Permission> permissions() {
        return mapper.findPermissions();
    }

    private static String normalize(String q) {
        if (q == null) {
            return null;
        }
        String trimmed = q.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
