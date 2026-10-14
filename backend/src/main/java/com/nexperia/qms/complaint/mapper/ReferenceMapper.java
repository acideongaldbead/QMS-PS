package com.nexperia.qms.complaint.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Collection;
import java.util.List;

/**
 * The checks that foreign keys cannot express.
 *
 * A FK proves a referenced row exists; it cannot prove that the chosen L2 failure
 * type sits under the chosen L1, or that a contact and a ship-to plant actually
 * belong to the selected customer. Those rules live here so the user gets a clear
 * message instead of a raw constraint name.
 *
 * Callers must not pass empty collections: the {@code <foreach>} would emit an
 * empty IN list, which is invalid SQL.
 */
@Mapper
public interface ReferenceMapper {

    /** Which of these dictionary codes exist and are usable. */
    @Select("""
            <script>
            SELECT code FROM master_data_item
             WHERE is_active = true AND is_deleted = false
               AND code IN <foreach item="c" collection="codes" open="(" separator="," close=")">#{c}</foreach>
            </script>
            """)
    List<String> findActiveDictionaryCodes(@Param("codes") Collection<String> codes);

    @Select("""
            <script>
            SELECT employee_id FROM employee
             WHERE is_active = true AND is_deleted = false
               AND employee_id IN <foreach item="i" collection="ids" open="(" separator="," close=")">#{i}</foreach>
            </script>
            """)
    List<String> findActiveEmployeeIds(@Param("ids") Collection<String> ids);

    /** code + level + parent code, to verify the L1 > L2 > L3 chain. */
    @Select("""
            <script>
            SELECT f.code AS code, f.level_no AS levelno, p.code AS parentcode
              FROM failure_type f
              LEFT JOIN failure_type p ON p.failure_type_id = f.parent_id
             WHERE f.is_active = true AND f.is_deleted = false
               AND f.code IN <foreach item="c" collection="codes" open="(" separator="," close=")">#{c}</foreach>
            </script>
            """)
    List<FailureTypeHierarchy> findFailureTypeHierarchy(@Param("codes") Collection<String> codes);

    @Select("SELECT count(*) FROM customer WHERE customer_code = #{code} AND is_active = true AND is_deleted = false")
    int countCustomer(@Param("code") String code);

    /**
     * A contact must belong to the customer on the same complaint; otherwise the
     * 8D report would be addressed to the wrong company's contact.
     */
    @Select("""
            SELECT count(*) FROM contact_person
             WHERE contact_id = #{contactId} AND customer_code = #{customerCode}
               AND is_active = true AND is_deleted = false
            """)
    int countContactOfCustomer(@Param("contactId") String contactId,
                               @Param("customerCode") String customerCode);

    @Select("""
            SELECT count(*) FROM ship_to_sold_to
             WHERE ship_to_code = #{shipToCode} AND customer_code = #{customerCode}
               AND is_active = true AND is_deleted = false
            """)
    int countShipToOfCustomer(@Param("shipToCode") String shipToCode,
                              @Param("customerCode") String customerCode);

    @Select("SELECT count(*) FROM product_master WHERE material_code = #{code} AND is_active = true AND is_deleted = false")
    int countProduct(@Param("code") String code);

    record FailureTypeHierarchy(String code, int levelno, String parentcode) {
    }
}
