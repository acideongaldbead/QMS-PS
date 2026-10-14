package com.nexperia.qms.logistics;

import java.util.Set;

/**
 * The shipment lifecycle (requirement 3.2.1 "Shipment Status").
 *
 * These codes correspond to rows seeded into {@code status_code} as
 * entity_name='Shipment', which is where the UI resolves the display names. The
 * column itself is not foreign-keyed, so this class is the application-side
 * authority for which codes are valid.
 */
public final class ShipmentStatus {

    public static final String PREPARING = "SHIPMENT_PREPARING";
    public static final String IN_TRANSIT = "SHIPMENT_IN_TRANSIT";
    public static final String RECEIVED = "SHIPMENT_RECEIVED";
    public static final String CLOSED = "SHIPMENT_CLOSED";

    public static final String DEFAULT = PREPARING;

    /** Arriving at one of these means the shipment is done, so the close date is stamped. */
    private static final Set<String> TERMINAL = Set.of(RECEIVED, CLOSED);

    private ShipmentStatus() {
    }

    public static boolean isKnown(String code) {
        return PREPARING.equals(code) || IN_TRANSIT.equals(code)
                || RECEIVED.equals(code) || CLOSED.equals(code);
    }

    /**
     * The null check matters: {@code Set.of(...)} builds an immutable set, whose
     * contains(null) throws NullPointerException rather than returning false.
     */
    public static boolean isTerminal(String code) {
        return code != null && TERMINAL.contains(code);
    }
}
