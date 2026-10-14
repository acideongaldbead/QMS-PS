package com.nexperia.qms.actions;

/**
 * The D7 prevention-file lifecycle. Seeded in status_code (V4) with entity_name
 * 'PreventionFileUpdate'.
 *
 * The schema notes that every file must be complete before the complaint can move
 * into D8, which is enforced when the report stage is reached.
 */
public final class PreventionStatus {

    public static final String TODO = "PREV_TODO";
    public static final String DOING = "PREV_DOING";
    public static final String DONE = "PREV_DONE";

    public static final String DEFAULT = TODO;

    private PreventionStatus() {
    }

    public static boolean isKnown(String code) {
        return TODO.equals(code) || DOING.equals(code) || DONE.equals(code);
    }

    public static boolean isComplete(String code) {
        return DONE.equals(code);
    }
}
