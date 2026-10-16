package com.nexperia.qms.masterdata;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.masterdata.dto.MasterDataAdminDtos;
import com.nexperia.qms.masterdata.mapper.MasterDataAdminMapper;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Maintenance of the platform's own reference data (PS-109 dictionary entries,
 * PS-036 the three-level failure type tree).
 *
 * Everything here is the first write path onto those two tables -- until now they
 * were seeded by migrations and only ever read. Three rules shape the design:
 *
 *  - a code is the business key. Business rows reference it by foreign key, so it
 *    is immutable once created; only names, sort order and the active flag move.
 *  - an entry is never deleted while something depends on it. Children are checked
 *    here, business references are left to the foreign keys, and either way the
 *    caller is told to deactivate instead.
 *  - no migration was needed. Making the code reusable after a soft delete would
 *    have required a partial unique index, and PostgreSQL does not let a foreign
 *    key point at one -- both codes are referenced by many tables.
 */
@Service
public class MasterDataAdminService {

    private static final String BIZ_ITEM = "MasterDataItem";
    private static final String BIZ_FAILURE_TYPE = "FailureType";

    /**
     * The priority list is deliberately not editable: its target days come from
     * {@code qms.priority.target-days} (see PriorityProperties), not from the
     * dictionary, so a new code here would silently mean "14 days" while the
     * screen showed nothing. Both sides must agree, so the type stays read-only.
     */
    private static final String READONLY_TYPE = "priority";

    private static final Pattern CODE_CHAR = Pattern.compile("[0-9A-Za-z]");
    private static final int MAX_FAILURE_LEVEL = 3;

    private final MasterDataAdminMapper mapper;
    private final AuditLogService auditLogService;

    public MasterDataAdminService(MasterDataAdminMapper mapper, AuditLogService auditLogService) {
        this.mapper = mapper;
        this.auditLogService = auditLogService;
    }

    // ---------------------------------------------------------------- dictionary

    @Transactional(readOnly = true)
    public List<MasterDataAdminDtos.DictionaryType> dictionaryTypes() {
        List<MasterDataAdminDtos.DictionaryType> types = new ArrayList<>();
        for (MasterDataAdminDtos.DictionaryTypeRow row : mapper.findDictionaryTypes()) {
            types.add(new MasterDataAdminDtos.DictionaryType(
                    row.mdType(), row.total(), row.active(), !READONLY_TYPE.equals(row.mdType())));
        }
        return types;
    }

    @Transactional(readOnly = true)
    public List<MasterDataAdminDtos.ItemView> items(String mdType) {
        requireKnownType(mdType);
        return mapper.findItems(mdType);
    }

    @Transactional
    public void createItem(String mdType, MasterDataAdminDtos.DictionaryCreateRequest request) {
        requireEditableType(mdType);
        String code = require(request.code());
        // The unique constraint is on the whole table, not on (md_type, code).
        if (mapper.findItem(code) != null) {
            throw new IllegalStateException("编码已存在：" + code);
        }
        Integer sortOrder = request.sortOrder() != null
                ? request.sortOrder()
                : mapper.nextItemSortOrder(mdType);
        mapper.insertItem(mdType, code, require(request.nameCn()),
                trimToNull(request.nameEn()), sortOrder, requireOperator());
        auditLogService.record(AuditActions.CREATE, BIZ_ITEM, code,
                "新增主数据项：" + mdType + " / " + code);
    }

    @Transactional
    public void updateItem(String mdType, String code,
                           MasterDataAdminDtos.DictionaryUpdateRequest request) {
        MasterDataAdminDtos.ItemView before = requireItem(mdType, code);
        requireEditableType(mdType);
        requireQmsOwned(before);

        mapper.updateItem(before.id(), require(request.nameCn()),
                trimToNull(request.nameEn()), request.sortOrder(), requireOperator());
        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_ITEM, code,
                describe(before), describe(requireItem(mdType, code)));
    }

    @Transactional
    public void setItemActive(String mdType, String code, boolean active) {
        MasterDataAdminDtos.ItemView item = requireItem(mdType, code);
        requireEditableType(mdType);
        requireQmsOwned(item);
        if (item.active() == active) {
            return;
        }
        mapper.updateItemActive(item.id(), active, requireOperator());
        auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, BIZ_ITEM, code,
                item.active() ? "启用" : "停用", active ? "启用" : "停用");
    }

    /** Physical: a code has to become reusable, and a partial index is not an option here. */
    @Transactional
    public void deleteItem(String mdType, String code) {
        MasterDataAdminDtos.ItemView item = requireItem(mdType, code);
        requireEditableType(mdType);
        requireQmsOwned(item);
        if (mapper.countItemChildren(item.id()) > 0) {
            throw new IllegalStateException("该主数据项还有下级，不能删除；请改为停用");
        }
        try {
            mapper.deleteItem(item.id());
        } catch (DataIntegrityViolationException e) {
            // The self-reference is ON DELETE SET NULL, but every business reference
            // is ON DELETE RESTRICT -- that is the authority on "is it in use".
            throw new IllegalStateException("该编码已被业务数据引用，不能删除；请改为停用");
        }
        auditLogService.record(AuditActions.DELETE, BIZ_ITEM, code,
                "删除主数据项：" + mdType + " / " + code + " " + item.nameCn());
    }

    // -------------------------------------------------------------- failure type

    @Transactional(readOnly = true)
    public List<MasterDataAdminDtos.FailureTypeNode> failureTypeTree() {
        return buildTree(mapper.findFailureTypeRows());
    }

    @Transactional
    public void createFailureType(MasterDataAdminDtos.FailureTypeCreateRequest request) {
        String code = require(request.code());
        String parentCode = trimToNull(request.parentCode());

        MasterDataAdminDtos.FailureTypeRow parent = null;
        int levelNo = 1;
        if (parentCode == null) {
            requireRootCode(code);
        } else {
            parent = mapper.findFailureType(parentCode);
            if (parent == null) {
                throw new NotFoundException("上级失效类型不存在：" + parentCode);
            }
            if (!parent.active()) {
                // Same invariant as re-enabling: an active node must have an active
                // parent, or no picker could reach the new one.
                throw new IllegalStateException("请先启用上级失效类型");
            }
            levelNo = parent.levelNo() + 1;
            if (levelNo > MAX_FAILURE_LEVEL) {
                throw new IllegalArgumentException("失效类型最多支持三级，不能在三级项下继续新增");
            }
            requireChildCode(code, parent.code());
        }
        if (mapper.findFailureType(code) != null) {
            throw new IllegalStateException("编码已存在：" + code);
        }

        mapper.insertFailureType(levelNo, code, require(request.name()),
                parent == null ? null : parent.id(), requireOperator());
        auditLogService.record(AuditActions.CREATE, BIZ_FAILURE_TYPE, code,
                "新增失效类型：L" + levelNo + " " + code
                        + (parent == null ? "" : "（上级 " + parent.code() + "）"));
    }

    @Transactional
    public void renameFailureType(String code, MasterDataAdminDtos.FailureTypeUpdateRequest request) {
        MasterDataAdminDtos.FailureTypeRow before = requireFailureType(code);
        String name = require(request.name());
        mapper.updateFailureTypeName(before.id(), name, requireOperator());
        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_FAILURE_TYPE, code,
                before.name(), name);
    }

    @Transactional
    public void setFailureTypeActive(String code, boolean active) {
        MasterDataAdminDtos.FailureTypeRow node = requireFailureType(code);
        if (node.active() == active) {
            return;
        }
        if (active && node.parentId() != null && mapper.countActiveById(node.parentId()) == 0) {
            // Otherwise the node comes back but no picker can reach it.
            throw new IllegalStateException("请先启用上级失效类型");
        }
        if (active) {
            mapper.updateFailureTypeActive(node.id(), true, requireOperator());
        } else {
            mapper.deactivateFailureTypeSubtree(node.id(), requireOperator());
        }
        auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, BIZ_FAILURE_TYPE, code,
                node.active() ? "启用" : "停用", active ? "启用" : "停用");
    }

    @Transactional
    public void deleteFailureType(String code) {
        MasterDataAdminDtos.FailureTypeRow node = requireFailureType(code);
        if (mapper.countFailureTypeChildren(node.id()) > 0) {
            throw new IllegalStateException("该失效类型还有下级，不能删除；请改为停用");
        }
        try {
            mapper.deleteFailureType(node.id());
        } catch (DataIntegrityViolationException e) {
            // sample and verification_result reference it by code, RESTRICT.
            throw new IllegalStateException("该编码已被样品或验证结果引用，不能删除；请改为停用");
        }
        auditLogService.record(AuditActions.DELETE, BIZ_FAILURE_TYPE, code,
                "删除失效类型：L" + node.levelNo() + " " + code + " " + node.name());
    }

    // -------------------------------------------------------------------- helpers

    private List<MasterDataAdminDtos.FailureTypeNode> buildTree(
            List<MasterDataAdminDtos.FailureTypeRow> rows) {
        Map<Long, List<MasterDataAdminDtos.FailureTypeRow>> byParent = new HashMap<>();
        for (MasterDataAdminDtos.FailureTypeRow row : rows) {
            byParent.computeIfAbsent(row.parentId(), key -> new ArrayList<>()).add(row);
        }
        return byParent.getOrDefault(null, List.of()).stream()
                .map(row -> attachChildren(row, byParent))
                .toList();
    }

    private MasterDataAdminDtos.FailureTypeNode attachChildren(
            MasterDataAdminDtos.FailureTypeRow row,
            Map<Long, List<MasterDataAdminDtos.FailureTypeRow>> byParent) {
        List<MasterDataAdminDtos.FailureTypeNode> children = byParent.getOrDefault(row.id(), List.of())
                .stream()
                .map(child -> attachChildren(child, byParent))
                .toList();
        return new MasterDataAdminDtos.FailureTypeNode(
                row.id(), row.code(), row.name(), row.levelNo(), row.active(), row.parentId(), children);
    }

    /** The code carries the level: '2' -> L1, '2a' -> L2, '2aa' -> L3 (requirement 3.3). */
    private static void requireRootCode(String code) {
        if (code.length() != 1 || !CODE_CHAR.matcher(code).matches()) {
            throw new IllegalArgumentException("一级失效类型编码必须是 1 个字母或数字，例如 2");
        }
    }

    private static void requireChildCode(String code, String parentCode) {
        boolean followsParent = code.length() == parentCode.length() + 1
                && code.startsWith(parentCode)
                && CODE_CHAR.matcher(code.substring(code.length() - 1)).matches();
        if (!followsParent) {
            throw new IllegalArgumentException(
                    "下级编码必须以上级编码开头并多 1 个字符，例如 " + parentCode + " 之下应为 "
                            + parentCode + "a；当前为 " + code);
        }
    }

    /**
     * The list of types is derived from the data rather than hard-coded, so a type
     * a later migration adds shows up without a code change.
     */
    private void requireKnownType(String mdType) {
        if (trimToNull(mdType) == null || mapper.countItemsOfType(mdType) == 0) {
            throw new NotFoundException("未知的主数据类型：" + mdType);
        }
    }

    private void requireEditableType(String mdType) {
        requireKnownType(mdType);
        if (READONLY_TYPE.equals(mdType)) {
            throw new IllegalStateException("优先级的目标天数由系统配置决定，不能在界面维护");
        }
    }

    private static void requireQmsOwned(MasterDataAdminDtos.ItemView item) {
        if (!"QMS".equals(item.sourceSystem())) {
            throw new IllegalStateException("该主数据来自 " + item.sourceSystem() + "，不能在 QMS 维护");
        }
    }

    private MasterDataAdminDtos.ItemView requireItem(String mdType, String code) {
        MasterDataAdminDtos.ItemView item = mapper.findItem(code);
        if (item == null || !item.mdType().equals(mdType)) {
            throw new NotFoundException("主数据项不存在：" + code);
        }
        return item;
    }

    private MasterDataAdminDtos.FailureTypeRow requireFailureType(String code) {
        MasterDataAdminDtos.FailureTypeRow node = mapper.findFailureType(code);
        if (node == null) {
            throw new NotFoundException("失效类型不存在：" + code);
        }
        return node;
    }

    private static String describe(MasterDataAdminDtos.ItemView item) {
        return "名称=" + item.nameCn() + "；英文名=" + orDash(item.nameEn())
                + "；排序=" + (item.sortOrder() == null ? "-" : item.sortOrder())
                + "；状态=" + (item.active() ? "启用" : "停用");
    }

    private static String orDash(String value) {
        return value == null || value.isBlank() ? "-" : value;
    }

    private static String require(String value) {
        String trimmed = trimToNull(value);
        if (trimmed == null) {
            throw new IllegalArgumentException("该项不能为空");
        }
        return trimmed;
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String requireOperator() {
        String operator = CurrentUserContext.employeeId();
        if (operator == null) {
            throw new IllegalStateException("未登录或登录已过期");
        }
        return operator;
    }
}
