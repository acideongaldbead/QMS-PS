package com.nexperia.qms.rootcause;

/**
 * The D4 root-cause lifecycle. Seeded in status_code (V4) with entity_name
 * 'RootCause', which is where the UI resolves the display names.
 */
public final class RootCauseStatus {

    public static final String TODO = "ROOTCAUSE_TODO";
    public static final String DOING = "ROOTCAUSE_DOING";
    public static final String DONE = "ROOTCAUSE_DONE";

    public static final String DEFAULT = TODO;

    private RootCauseStatus() {
    }

    public static boolean isKnown(String code) {
        return TODO.equals(code) || DOING.equals(code) || DONE.equals(code);
    }
}
