package com.nexperia.qms.verification;

import java.util.Set;

/**
 * The D2 task lifecycle.
 *
 * Like the shipment status, {@code verification_task.task_status} is free text
 * with no foreign key; these codes are seeded into {@code status_code} with
 * entity_name='VerificationTask' as the source of display names.
 */
public final class VerificationTaskStatus {

    public static final String TODO = "VERIF_TODO";
    public static final String SCHEDULED = "VERIF_SCHEDULED";
    public static final String DOING = "VERIF_DOING";
    public static final String DONE = "VERIF_DONE";
    public static final String CANCELLED = "VERIF_CANCELLED";

    private static final Set<String> ALL = Set.of(TODO, SCHEDULED, DOING, DONE, CANCELLED);

    /** Statuses after which no further results should be recorded. */
    private static final Set<String> CLOSED_FOR_ENTRY = Set.of(DONE, CANCELLED);

    private VerificationTaskStatus() {
    }

    public static boolean isKnown(String code) {
        return code != null && ALL.contains(code);
    }

    public static boolean isClosedForEntry(String code) {
        return code != null && CLOSED_FOR_ENTRY.contains(code);
    }
}
