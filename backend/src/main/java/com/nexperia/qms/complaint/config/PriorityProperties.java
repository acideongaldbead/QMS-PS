package com.nexperia.qms.complaint.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * How many calendar days each priority gets for the target date.
 *
 * This mapping is NOT in the database: master_data_item seeds the three priority
 * codes with names only, because the requirements state the rule as
 * "非常紧急 7 / 紧急 10 / 标准 14" without describing a place to store it. Keeping
 * it in configuration makes it visible and changeable without a migration.
 *
 * Note the codes are not in the intuitive order -- PRIORITY_003 is the most
 * urgent.
 */
@Component
@ConfigurationProperties(prefix = "qms.priority")
@Data
public class PriorityProperties {

    /** priority_code -> calendar days added to the start date. */
    private Map<String, Integer> targetDays = new LinkedHashMap<>();

    /** Used when a priority has no configured value, rather than failing the request. */
    private int fallbackTargetDays = 14;

    public int targetDaysFor(String priorityCode) {
        Integer days = targetDays.get(priorityCode);
        return days == null ? fallbackTargetDays : days;
    }
}
