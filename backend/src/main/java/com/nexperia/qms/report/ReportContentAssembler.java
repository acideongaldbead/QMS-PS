package com.nexperia.qms.report;

import com.nexperia.qms.actions.CorrectiveActionService;
import com.nexperia.qms.actions.PreventionService;
import com.nexperia.qms.complaint.ComplaintService;
import com.nexperia.qms.containment.ContainmentService;
import com.nexperia.qms.report.dto.ReportDtos;
import com.nexperia.qms.report.mapper.ReportDistributionMapper;
import com.nexperia.qms.report.mapper.ReportTeamMemberMapper;
import com.nexperia.qms.rootcause.RootCauseService;
import com.nexperia.qms.verification.VerificationService;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Gathers the D1-D7 content the report is built from.
 *
 * It reuses each stage's own read method rather than re-querying the tables, so the
 * report can never drift from what the detail screens show: whatever the engineer
 * last saved is what the report prints.
 */
@Component
public class ReportContentAssembler {

    private final ComplaintService complaintService;
    private final ContainmentService containmentService;
    private final VerificationService verificationService;
    private final RootCauseService rootCauseService;
    private final CorrectiveActionService correctiveActionService;
    private final PreventionService preventionService;
    private final ReportTeamMemberMapper teamMemberMapper;
    private final ReportDistributionMapper distributionMapper;

    public ReportContentAssembler(ComplaintService complaintService,
                                  ContainmentService containmentService,
                                  VerificationService verificationService,
                                  RootCauseService rootCauseService,
                                  CorrectiveActionService correctiveActionService,
                                  PreventionService preventionService,
                                  ReportTeamMemberMapper teamMemberMapper,
                                  ReportDistributionMapper distributionMapper) {
        this.complaintService = complaintService;
        this.containmentService = containmentService;
        this.verificationService = verificationService;
        this.rootCauseService = rootCauseService;
        this.correctiveActionService = correctiveActionService;
        this.preventionService = preventionService;
        this.teamMemberMapper = teamMemberMapper;
        this.distributionMapper = distributionMapper;
    }

    public ReportDtos.ReportContent assemble(ReportDtos.ReportView report) {
        String complaintId = report.complaintId();
        List<ReportDtos.TeamMemberView> team = teamMemberMapper.findByReport(report.reportId()).stream()
                .map(m -> new ReportDtos.TeamMemberView(
                        m.getFunctionName(), m.getMemberName(), m.getJobTitle(), m.getEmployeeId()))
                .toList();
        List<ReportDtos.DistributionView> distributions = distributionMapper.findByReport(report.reportId()).stream()
                .map(d -> new ReportDtos.DistributionView(
                        d.logId(), d.senderName(), d.recipient(), d.ccList(),
                        d.sentAt(), d.attachmentVersion(), d.channel()))
                .toList();

        return new ReportDtos.ReportContent(
                report,
                complaintService.getDetail(complaintId),
                team,
                containmentService.summary(complaintId),
                verificationService.listTasks(complaintId),
                rootCauseService.list(complaintId),
                correctiveActionService.list(complaintId),
                preventionService.list(complaintId),
                distributions);
    }
}
