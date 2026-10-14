package com.nexperia.qms.actions;

/**
 * The D5/D6 corrective-action lifecycle. Seeded in status_code (V4) with
 * entity_name 'CorrectiveAction'.
 *
 * The path is: to-do -> in progress -> implemented -> verified, with a branch back
 * to failed when the D6 verification does not pass (PS-054, "rework on failure").
 */
public final class CorrectiveStatus {

    public static final String TODO = "CORR_TODO";
    public static final String DOING = "CORR_DOING";
    public static final String DONE = "CORR_DONE";
    public static final String VERIFIED = "CORR_VERIFIED";

    /** Set automatically when a verification reports the action as ineffective. */
    public static final String FAILED = "CORR_FAILED";

    public static final String DEFAULT = TODO;

    private CorrectiveStatus() {
    }

    public static boolean isKnown(String code) {
        return TODO.equals(code) || DOING.equals(code) || DONE.equals(code)
                || VERIFIED.equals(code) || FAILED.equals(code);
    }
}
