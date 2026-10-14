package com.nexperia.qms.containment;

import java.util.Set;

/**
 * The D3 containment action lifecycle.
 *
 * These codes are seeded in {@code status_code} (V4) with entity_name
 * 'ContainmentAction', which is where the UI resolves their display names. The
 * column is foreign-keyed, so this class only needs to know which codes are valid.
 */
public final class ContainmentStatus {

    public static final String TODO = "CONTAIN_TODO";
    public static final String DOING = "CONTAIN_DOING";
    public static final String DONE = "CONTAIN_DONE";
    public static final String CANCELLED = "CONTAIN_CANCELLED";

    public static final String DEFAULT = TODO;

    /** Reaching one of these means the action is finished, so the completion date is stamped. */
    private static final Set<String> TERMINAL = Set.of(DONE, CANCELLED);

    private ContainmentStatus() {
    }

    public static boolean isKnown(String code) {
        return TODO.equals(code) || DOING.equals(code) || DONE.equals(code) || CANCELLED.equals(code);
    }

    /**
     * The null check is not decoration: {@code Set.of(...)} builds an immutable
     * set, whose contains(null) throws NullPointerException rather than returning
     * false. A brand new action has no previous status, so null does arrive here.
     */
    public static boolean isTerminal(String code) {
        return code != null && TERMINAL.contains(code);
    }
}
