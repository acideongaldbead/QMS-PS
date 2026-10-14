package com.nexperia.qms.masterdata.dto;

import java.util.List;

/**
 * Response shapes for the master-data read APIs. Grouped in one holder so the
 * whole contract is visible in a single file; each is referenced as
 * {@code MasterDataDtos.Xxx}.
 */
public final class MasterDataDtos {

    private MasterDataDtos() {
    }

    /** One dictionary entry (complaint type, priority, packing type, ...). */
    public record Item(String code, String nameCn, String nameEn, Integer sortOrder) {
    }

    /** A simple coded option: ship-to plants, file types, and similar. */
    public record Option(String code, String name) {
    }

    /**
     * Flat row of the failure type table. Kept separate from {@link FailureType}
     * because MyBatis builds records through the constructor and therefore needs
     * a column for every component -- the tree's children list has none.
     */
    public record FailureTypeRow(long id, int levelNo, String code, String name, Long parentId) {
    }

    /** Node of the three-level failure type tree. */
    public record FailureType(long id, int levelNo, String code, String name, Long parentId,
                              List<FailureType> children) {
    }

    public record Customer(String code, String name, String country, String city,
                           String streetAddress) {
    }

    public record Contact(String id, String name, String email, String phone) {
    }

    public record Product(String code, String description,
                          String productTypeCode, String productTypeName,
                          String packingTypeCode, String packingTypeName,
                          String businessGroup, String businessUnit) {
    }

    public record Employee(String id, String name, String nameEn, String email,
                           String deptL1, String deptL2, String jobTitle) {
    }

    public record Status(String code, String entityName, String nameCn, String nameEn,
                         Integer sortOrder, Boolean isFinal) {
    }

    public record Role(long id, String code, String name, String nameEn) {
    }

    public record Permission(String code, String name, String nameEn, String level, String module) {
    }
}
