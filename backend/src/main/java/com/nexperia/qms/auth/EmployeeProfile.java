package com.nexperia.qms.auth;

import lombok.Data;

/** Read-only projection of {@code employee} for the signed-in user. */
@Data
public class EmployeeProfile {

    private String employeeId;
    private String name;
    private String nameEn;
    private String email;
    private String deptL1;
    private String deptL2;
    private String jobTitle;
}
