package com.nexperia.qms.home;

import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.ComplaintService;
import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import com.nexperia.qms.home.dto.HomeDtos;
import com.nexperia.qms.home.mapper.HomeMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * The home page (requirement 3.0): what is waiting for the current user, the
 * four figures and the complaints behind the overdue banner.
 *
 * The work list is assembled from real outstanding records, so closing a task
 * removes its entry - a complaint that merely sits at D4 does not produce a
 * "root cause" entry if the root causes are already written.
 */
@Service
public class HomeService {

    /** The list shows the most urgent few; the rest are reachable from the ledger. */
    private static final int TODO_DISPLAY_CAP = 12;

    /** The banner names the worst few rather than every late complaint. */
    private static final int OVERDUE_BANNER_SIZE = 4;

    /** The biggest page the ledger accepts, used to then slice the banner rows. */
    private static final int OVERDUE_QUERY_SIZE = 20;

    private static final String PRIORITY_VERY_URGENT = "PRIORITY_003";

    /**
     * How each kind of outstanding record is presented and where it opens.
     *
     * The declaration order is the order the groups appear on the page, matching
     * the prototype's grouping.
     */
    private enum TodoType {
        REPORT_PENDING("待审批报告", "d8", "8D 报告待审批"),
        VERIFICATION("验证任务", "d2", "失效分析结果待录入"),
        CORRECTIVE("纠正措施", "d5", "纠正措施待分配与推进"),
        ROOT_CAUSE("根因分析", "d4", "根因分析待完成"),
        CONTAINMENT("遏制措施", "d3", "遏制措施待跟踪闭环"),
        SAMPLE_LOGISTICS("样品物流", "d01", "待补录样品与物流信息"),
        PREVENTION("预防文件", "d7", "预防文件更新待完成"),
        ACTION_VERIFICATION("措施验证", "d6", "措施验证结果待反馈"),
        REPORT("报告编制", "d8", "8D 报告待编制与提交");

        private final String label;
        private final String tab;
        private final String action;

        TodoType(String label, String tab, String action) {
            this.label = label;
            this.tab = tab;
            this.action = action;
        }
    }

    private final HomeMapper homeMapper;
    private final ComplaintService complaintService;

    public HomeService(HomeMapper homeMapper, ComplaintService complaintService) {
        this.homeMapper = homeMapper;
        this.complaintService = complaintService;
    }

    @Transactional(readOnly = true)
    public HomeDtos.HomeOverview overview() {
        String me = CurrentUserContext.employeeId();

        List<HomeMapper.TodoRow> rows = new ArrayList<>();
        rows.addAll(homeMapper.findOutstandingVerificationTasks(me));
        rows.addAll(homeMapper.findOutstandingContainmentActions(me));
        rows.addAll(homeMapper.findOutstandingCorrectiveActions(me));
        rows.addAll(homeMapper.findActionsAwaitingVerification(me));
        rows.addAll(homeMapper.findOutstandingPreventionFiles(me));
        rows.addAll(homeMapper.findDraftReports(me));
        rows.addAll(homeMapper.findPendingApprovals(me));
        rows.addAll(homeMapper.findRootCauseWork(me));
        rows.addAll(homeMapper.findSampleLogisticsWork(me));

        // collect(toList()) rather than Stream.toList(): the result is sorted below.
        List<HomeDtos.TodoItem> todos = rows.stream().map(this::toItem).collect(Collectors.toList());

        // Overdue first, then the nearest deadline, then the group order so the
        // list does not reshuffle between two loads of the same data.
        todos.sort((a, b) -> {
            boolean aOverdue = a.overdueDays() > 0;
            boolean bOverdue = b.overdueDays() > 0;
            if (aOverdue != bOverdue) {
                return aOverdue ? -1 : 1;
            }
            int byDue = compareDates(a.dueDate(), b.dueDate());
            if (byDue != 0) {
                return byDue;
            }
            return Integer.compare(TodoType.valueOf(a.type()).ordinal(), TodoType.valueOf(b.type()).ordinal());
        });

        int todoCount = todos.size();
        int typeCount = (int) todos.stream().map(HomeDtos.TodoItem::type).distinct().count();
        int urgentCount = (int) todos.stream().filter(HomeDtos.TodoItem::urgent).count();

        List<HomeDtos.TodoItem> shown = todos.size() > TODO_DISPLAY_CAP
                ? List.copyOf(todos.subList(0, TODO_DISPLAY_CAP))
                : List.copyOf(todos);

        // The banner is the whole backlog, not just the user's own: a late
        // complaint is late for the company, not for one person.
        ComplaintResponses.LedgerPage overdue = complaintService.listLedger(
                new ComplaintRequests.LedgerQuery(
                        "all", null, null, null, null, null, null, null,
                        null, null, null, null,
                        true, true, null,
                        1, OVERDUE_QUERY_SIZE, "targetDate", "asc", null));

        HomeDtos.HomeStats stats = new HomeDtos.HomeStats(
                todoCount,
                typeCount,
                urgentCount,
                homeMapper.countPendingApprovalsFor(me),
                complaintService.countRelatedToMe());

        return new HomeDtos.HomeOverview(
                stats,
                shown,
                todoCount,
                overdue.items().stream().limit(OVERDUE_BANNER_SIZE).toList(),
                overdue.total());
    }

    private HomeDtos.TodoItem toItem(HomeMapper.TodoRow row) {
        TodoType type = TodoType.valueOf(row.taskType());
        LocalDate due = row.dueDate();
        int overdueDays = due == null
                ? 0
                : (int) Math.max(0, ChronoUnit.DAYS.between(due, LocalDate.now()));
        boolean urgent = overdueDays > 0 || PRIORITY_VERY_URGENT.equals(row.priorityCode());
        // The report rows carry the raw approval status; the other rows already
        // carry the dictionary's display name.
        String statusText = switch (row.taskType()) {
            case "REPORT" -> "DRAFT".equals(row.statusText()) ? "报告编制中" : "审批已驳回";
            default -> row.statusText();
        };

        return new HomeDtos.TodoItem(
                row.taskId(),
                row.taskType(),
                type.label,
                type.action,
                row.complaintId(),
                type.tab,
                due,
                overdueDays,
                urgent,
                statusText);
    }

    private static int compareDates(LocalDate a, LocalDate b) {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }
        return a.compareTo(b);
    }
}
