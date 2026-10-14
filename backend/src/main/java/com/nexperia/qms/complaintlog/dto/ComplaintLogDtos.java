package com.nexperia.qms.complaintlog.dto;

import java.time.OffsetDateTime;

public final class ComplaintLogDtos {

    private ComplaintLogDtos() {
    }

    /**
     * One line of the complaint's process and communication history.
     *
     * Both sources are flattened into the same shape so the client renders one
     * timeline: {@code kind} only says where the line came from.
     */
    public record LogEntry(
            OffsetDateTime at,
            /** AUDIT for the process trail, COMMUNICATION for a sent report. */
            String kind,
            /** Who did it; the code is returned when the person is unknown. */
            String actorName,
            /** e.g. "验证任务 · 新增" or "8D 报告 · 发送给客户". */
            String actionLabel,
            String detail,
            /** Timeline dot tone: done / warn / empty for neutral. */
            String tone) {
    }
}
