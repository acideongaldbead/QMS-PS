package com.nexperia.qms.masterdata.mapper;

import com.nexperia.qms.masterdata.dto.MasterDataAdminDtos;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

/**
 * Writes for the master data maintenance screens (PS-109 / PS-036).
 *
 * These are the first write paths onto {@code master_data_item} and
 * {@code failure_type}; every statement is explicit rather than going through a
 * MyBatis-Plus entity, so a null can actually be written (an omitted sort order)
 * and the soft-delete flag cannot be applied by accident.
 *
 * Deleting is PHYSICAL. Both tables' {@code code} columns are the target of
 * business foreign keys, which in PostgreSQL cannot reference a partial unique
 * index -- so the "soft delete frees the code" trick used on {@code role} and
 * {@code shipment_sample} is not available here. Physical delete, guarded by
 * "no children and nothing references it", is what lets a mis-typed code be
 * cleared and reused.
 */
@Mapper
public interface MasterDataAdminMapper {

    // ------------------------------------------------------------- dictionary

    @Select("""
            SELECT md_type AS mdType, count(*) AS total,
                   count(*) FILTER (WHERE is_active) AS active
              FROM master_data_item
             WHERE is_deleted = false
             GROUP BY md_type
             ORDER BY md_type
            """)
    List<MasterDataAdminDtos.DictionaryTypeRow> findDictionaryTypes();

    @Select("""
            SELECT md_id        AS id,            -- 1
                   md_type      AS mdType,        -- 2
                   code,                          -- 3
                   name_cn      AS nameCn,        -- 4
                   name_en      AS nameEn,        -- 5
                   sort_order   AS sortOrder,     -- 6
                   is_active    AS active,        -- 7
                   source_system AS sourceSystem  -- 8
              FROM master_data_item
             WHERE md_type = #{mdType} AND is_deleted = false
             ORDER BY sort_order NULLS LAST, code
            """)
    List<MasterDataAdminDtos.ItemView> findItems(@Param("mdType") String mdType);

    /** The dictionary code is unique across the whole table, not per type. */
    @Select("""
            SELECT md_id        AS id,            -- 1
                   md_type      AS mdType,        -- 2
                   code,                          -- 3
                   name_cn      AS nameCn,        -- 4
                   name_en      AS nameEn,        -- 5
                   sort_order   AS sortOrder,     -- 6
                   is_active    AS active,        -- 7
                   source_system AS sourceSystem  -- 8
              FROM master_data_item
             WHERE code = #{code} AND is_deleted = false
            """)
    MasterDataAdminDtos.ItemView findItem(@Param("code") String code);

    @Select("SELECT count(*) FROM master_data_item WHERE md_type = #{mdType} AND is_deleted = false")
    int countItemsOfType(@Param("mdType") String mdType);

    /** The self-referencing foreign key is ON DELETE SET NULL, so this must be checked here. */
    @Select("SELECT count(*) FROM master_data_item WHERE parent_id = #{id} AND is_deleted = false")
    int countItemChildren(@Param("id") long id);

    /**
     * A new entry with no sort order would sort last forever (the read side orders
     * by {@code sort_order NULLS LAST}), so it inherits the next free slot.
     */
    @Select("""
            SELECT coalesce(max(sort_order), 0) + 1
              FROM master_data_item
             WHERE md_type = #{mdType} AND is_deleted = false
            """)
    int nextItemSortOrder(@Param("mdType") String mdType);

    @Insert("""
            INSERT INTO master_data_item (md_type, code, name_cn, name_en, sort_order, source_system,
                                          is_active, created_by, updated_by, is_deleted)
            VALUES (#{mdType}, #{code}, #{nameCn}, #{nameEn}, #{sortOrder}, 'QMS',
                    true, #{operator}, #{operator}, false)
            """)
    int insertItem(@Param("mdType") String mdType,
                   @Param("code") String code,
                   @Param("nameCn") String nameCn,
                   @Param("nameEn") String nameEn,
                   @Param("sortOrder") Integer sortOrder,
                   @Param("operator") String operator);

    @Update("""
            UPDATE master_data_item
               SET name_cn = #{nameCn}, name_en = #{nameEn}, sort_order = #{sortOrder},
                   updated_by = #{operator}
             WHERE md_id = #{id}
            """)
    int updateItem(@Param("id") long id,
                   @Param("nameCn") String nameCn,
                   @Param("nameEn") String nameEn,
                   @Param("sortOrder") Integer sortOrder,
                   @Param("operator") String operator);

    @Update("UPDATE master_data_item SET is_active = #{active}, updated_by = #{operator} WHERE md_id = #{id}")
    int updateItemActive(@Param("id") long id,
                         @Param("active") boolean active,
                         @Param("operator") String operator);

    @Delete("DELETE FROM master_data_item WHERE md_id = #{id}")
    int deleteItem(@Param("id") long id);

    // ----------------------------------------------------------- failure type

    @Select("""
            SELECT failure_type_id AS id,        -- 1
                   code,                          -- 2
                   name,                          -- 3
                   level_no        AS levelNo,    -- 4
                   is_active       AS active,     -- 5
                   parent_id       AS parentId    -- 6
              FROM failure_type
             WHERE is_deleted = false
             ORDER BY code
            """)
    List<MasterDataAdminDtos.FailureTypeRow> findFailureTypeRows();

    @Select("""
            SELECT failure_type_id AS id,        -- 1
                   code,                          -- 2
                   name,                          -- 3
                   level_no        AS levelNo,    -- 4
                   is_active       AS active,     -- 5
                   parent_id       AS parentId    -- 6
              FROM failure_type
             WHERE code = #{code} AND is_deleted = false
            """)
    MasterDataAdminDtos.FailureTypeRow findFailureType(@Param("code") String code);

    @Select("SELECT count(*) FROM failure_type WHERE parent_id = #{id} AND is_deleted = false")
    int countFailureTypeChildren(@Param("id") long id);

    @Insert("""
            INSERT INTO failure_type (level_no, code, name, parent_id, is_active,
                                      created_by, updated_by, is_deleted)
            VALUES (#{levelNo}, #{code}, #{name}, #{parentId}, true,
                    #{operator}, #{operator}, false)
            """)
    int insertFailureType(@Param("levelNo") int levelNo,
                          @Param("code") String code,
                          @Param("name") String name,
                          @Param("parentId") Long parentId,
                          @Param("operator") String operator);

    @Update("UPDATE failure_type SET name = #{name}, updated_by = #{operator} WHERE failure_type_id = #{id}")
    int updateFailureTypeName(@Param("id") long id,
                              @Param("name") String name,
                              @Param("operator") String operator);

    @Update("UPDATE failure_type SET is_active = #{active}, updated_by = #{operator} WHERE failure_type_id = #{id}")
    int updateFailureTypeActive(@Param("id") long id,
                                @Param("active") boolean active,
                                @Param("operator") String operator);

    /**
     * Switching a branch off takes its whole subtree with it: the pickers read the
     * active-only tree, so active children under an inactive parent would be
     * unreachable anyway. Enabling is the opposite -- one row at a time -- so that
     * re-enabling a parent does not silently resurrect a deliberately disabled child.
     */
    @Update("""
            WITH RECURSIVE subtree AS (
                SELECT failure_type_id FROM failure_type WHERE failure_type_id = #{id}
                UNION ALL
                SELECT c.failure_type_id
                  FROM failure_type c
                  JOIN subtree s ON c.parent_id = s.failure_type_id
                 WHERE c.is_deleted = false
            )
            UPDATE failure_type
               SET is_active = false, updated_by = #{operator}
             WHERE failure_type_id IN (SELECT failure_type_id FROM subtree)
            """)
    int deactivateFailureTypeSubtree(@Param("id") long id, @Param("operator") String operator);

    @Delete("DELETE FROM failure_type WHERE failure_type_id = #{id}")
    int deleteFailureType(@Param("id") long id);

    /** Whether the parent chain is switched on, used when enabling a node again. */
    @Select("""
            SELECT count(*)
              FROM failure_type
             WHERE failure_type_id = #{id} AND is_active = true AND is_deleted = false
            """)
    int countActiveById(@Param("id") long id);
}
