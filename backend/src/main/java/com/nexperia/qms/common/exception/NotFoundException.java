package com.nexperia.qms.common.exception;

/** Thrown when a requested business record does not exist. */
public class NotFoundException extends RuntimeException {

    public NotFoundException(String message) {
        super(message);
    }
}
