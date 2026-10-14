package com.nexperia.qms.home.dto;

import com.nexperia.qms.complaint.dto.ComplaintResponses;

import java.time.LocalDate;
import java.util.List;

public final class HomeDtos {

    private HomeDtos() {
    }

    /**
     * One thing waiting for the current user (requirement 3.0's "我的待办").
     *
     * Built from a real outstanding record rather than derived from the stage the
     * complaint sits at, so finishing the work makes the entry disappear.
     */
    public record TodoItem(
            String todoId,
            /** Stable key, e.g. VERIFICATION; the client does not translate it. */
            String type,
            /** Grouping label, already localised server side. */
            String typeLabel,
            /** What has to be done, e.g. the D2 entry prompt. */
            String title,
            String complaintId,
            /** Which tab of the complaint detail the entry opens. */
            String tab,
            LocalDate dueDate,
            int overdueDays,
            boolean urgent,
            /** The record's own status, for the second line of the entry. */
            String statusText) {
    }

    /** The four figures across the top of the home page. */
    public record HomeStats(
            int todoCount,
            int todoTypeCount,
            int overdueTaskCount,
            long pendingApprovalCount,
            long myComplaintCount) {
    }

    /**
     * Everything the home page needs, in one call: the figures, the to-do list
     * (capped, with the uncapped total) and the complaints behind the overdue
     * banner. The banner rows reuse the ledger's row shape, so the two screens
     * cannot disagree about what "overdue" means.
     */
    public record HomeOverview(
            HomeStats stats,
            List<TodoItem> todos,
            /** Total before the display cap. */
            int todoTotal,
            List<ComplaintResponses.LedgerRow> overdueComplaints,
            long overdueComplaintTotal) {
    }
}
