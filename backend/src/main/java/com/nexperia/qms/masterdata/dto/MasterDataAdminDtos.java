package com.nexperia.qms.masterdata.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * Shapes for the master data maintenance screens (PS-109 / PS-036).
 *
 * Separate from {@link MasterDataDtos} on purpose: the read side of the platform
 * feeds every picker and is already verified, so nothing there changes. Here the
 * rows carry what only a maintenance screen needs -- {@code isActive} (so an
 * entry can be switched back on) and {@code sourceSystem} (so a row that came
 * from SAP is visibly not ours to edit).
 */
public final class MasterDataAdminDtos {

    private MasterDataAdminDtos() {
    }

    // ------------------------------------------------------------------ dictionary

    /** One maintainable dictionary type, for the left-hand list. */
    public record DictionaryType(String mdType, long total, long active, boolean editable) {
    }

    /** The mapper projection behind {@link DictionaryType}; {@code editable} is added in the service. */
    public record DictionaryTypeRow(String mdType, long total, long active) {
    }

    /**
     * One dictionary row, as both the mapper projection and the API response.
     * Column order in the select list must match the component order.
     */
    public record ItemView(
            long id,             // 1
            String mdType,       // 2
            String code,         // 3
            String nameCn,       // 4
            String nameEn,       // 5
            Integer sortOrder,   // 6
            boolean active,      // 7
            String sourceSystem) { // 8
    }

    /** Create: the code is supplied once and never changes afterwards. */
    public record DictionaryCreateRequest(
            @NotBlank(message = "编码不能为空")
            @Size(max = 32, message = "编码不能超过 32 个字符")
            String code,
            @NotBlank(message = "名称不能为空")
            @Size(max = 128, message = "名称不能超过 128 个字符")
            String nameCn,
            @Size(max = 128, message = "英文名不能超过 128 个字符")
            String nameEn,
            Integer sortOrder) {
    }

    /** Update: only these three move; the code travels in the path. */
    public record DictionaryUpdateRequest(
            @NotBlank(message = "名称不能为空")
            @Size(max = 128, message = "名称不能超过 128 个字符")
            String nameCn,
            @Size(max = 128, message = "英文名不能超过 128 个字符")
            String nameEn,
            Integer sortOrder) {
    }

    // --------------------------------------------------------------- failure type

    /** A node of the three-level failure type tree, inactive ones included. */
    public record FailureTypeNode(
            long id,
            String code,
            String name,
            int levelNo,
            boolean active,
            Long parentId,
            List<FailureTypeNode> children) {
    }

    /** The flat row MyBatis needs; the tree's children list has no column. */
    public record FailureTypeRow(
            long id,          // 1
            String code,      // 2
            String name,      // 3
            int levelNo,      // 4
            boolean active,   // 5
            Long parentId) {  // 6
    }

    /** Create: {@code parentCode} null means a level-1 node. */
    public record FailureTypeCreateRequest(
            String parentCode,
            @NotBlank(message = "编码不能为空")
            @Size(max = 32, message = "编码不能超过 32 个字符")
            String code,
            @NotBlank(message = "名称不能为空")
            @Size(max = 128, message = "名称不能超过 128 个字符")
            String name) {
    }

    /** Rename only: the code carries the level, and business rows reference it. */
    public record FailureTypeUpdateRequest(
            @NotBlank(message = "名称不能为空")
            @Size(max = 128, message = "名称不能超过 128 个字符")
            String name) {
    }
}
