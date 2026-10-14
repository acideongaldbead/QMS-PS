package com.nexperia.qms.masterdata.mapper;

import com.nexperia.qms.masterdata.dto.MasterDataDtos;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

/**
 * Read-only queries behind the reference-data pickers. Searchable endpoints filter
 * with a case-insensitive match and are capped, since these lists back dropdowns
 * rather than paged tables.
 */
@Mapper
public interface MasterDataMapper {

    int OPTION_LIMIT = 200;

    @Select("""
            SELECT code, name_cn, name_en, sort_order
              FROM master_data_item
             WHERE md_type = #{mdType} AND is_active = true AND is_deleted = false
             ORDER BY sort_order NULLS LAST, code
            """)
    List<MasterDataDtos.Item> findDictionary(@Param("mdType") String mdType);

    @Select("""
            SELECT failure_type_id AS id, level_no AS levelno, code, name, parent_id AS parentid
              FROM failure_type
             WHERE is_active = true AND is_deleted = false
             ORDER BY level_no, code
            """)
    List<MasterDataDtos.FailureTypeRow> findFailureTypeRows();

    @Select("""
            <script>
            SELECT customer_code AS code, customer_name AS name, country, city,
                   street_address AS streetAddress
              FROM customer
             WHERE is_active = true AND is_deleted = false
             <if test="q != null and q != ''">
               AND (customer_name ILIKE '%' || #{q} || '%' OR customer_code ILIKE '%' || #{q} || '%')
             </if>
             ORDER BY customer_code
             LIMIT 200
            </script>
            """)
    List<MasterDataDtos.Customer> findCustomers(@Param("q") String q);

    @Select("""
            SELECT ship_to_code AS code, ship_to_name AS name
              FROM ship_to_sold_to
             WHERE customer_code = #{customerCode} AND is_active = true AND is_deleted = false
             ORDER BY ship_to_code
            """)
    List<MasterDataDtos.Option> findShipTo(@Param("customerCode") String customerCode);

    @Select("""
            SELECT contact_id AS id, contact_name AS name, email, phone
              FROM contact_person
             WHERE customer_code = #{customerCode} AND is_active = true AND is_deleted = false
             ORDER BY contact_id
            """)
    List<MasterDataDtos.Contact> findContacts(@Param("customerCode") String customerCode);

    @Select("""
            <script>
            SELECT pm.material_code AS code, pm.description,
                   pm.product_type_code AS productTypeCode, pt.name_cn AS productTypeName,
                   pm.packing_type_code AS packingTypeCode, pk.name_cn AS packingTypeName,
                   pm.business_group AS businessGroup, pm.business_unit AS businessUnit
              FROM product_master pm
              LEFT JOIN master_data_item pt ON pt.code = pm.product_type_code
              LEFT JOIN master_data_item pk ON pk.code = pm.packing_type_code
             WHERE pm.is_active = true AND pm.is_deleted = false
             <if test="q != null and q != ''">
               AND (pm.material_code ILIKE '%' || #{q} || '%' OR pm.description ILIKE '%' || #{q} || '%')
             </if>
             ORDER BY pm.material_code
             LIMIT 200
            </script>
            """)
    List<MasterDataDtos.Product> findProducts(@Param("q") String q);

    @Select("""
            <script>
            SELECT employee_id AS id, name, name_en AS nameEn, email,
                   dept_l1 AS deptL1, dept_l2 AS deptL2, job_title AS jobTitle
              FROM employee
             WHERE is_active = true AND is_deleted = false
             <if test="q != null and q != ''">
               AND (name ILIKE '%' || #{q} || '%' OR name_en ILIKE '%' || #{q} || '%'
                    OR employee_id ILIKE '%' || #{q} || '%')
             </if>
             ORDER BY employee_id
             LIMIT 200
            </script>
            """)
    List<MasterDataDtos.Employee> findEmployees(@Param("q") String q);

    @Select("""
            <script>
            SELECT status_code AS code, entity_name AS entityName, name_cn AS nameCn,
                   name_en AS nameEn, sort_order AS sortOrder, is_final AS isFinal
              FROM status_code
             WHERE is_deleted = false
             <if test="entityName != null and entityName != ''">
               AND entity_name = #{entityName}
             </if>
             ORDER BY entity_name, sort_order NULLS LAST, status_code
            </script>
            """)
    List<MasterDataDtos.Status> findStatusCodes(@Param("entityName") String entityName);

    @Select("""
            SELECT role_id AS id, role_code AS code, role_name AS name, role_name_en AS nameEn
              FROM role
             WHERE is_deleted = false
             ORDER BY role_id
            """)
    List<MasterDataDtos.Role> findRoles();

    @Select("""
            SELECT permission_code AS code, permission_name AS name, permission_name_en AS nameEn,
                   permission_level AS level, module_code AS module
              FROM permission
             WHERE is_deleted = false
             ORDER BY module_code NULLS LAST, permission_code
            """)
    List<MasterDataDtos.Permission> findPermissions();
}
