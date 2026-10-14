package com.nexperia.qms.common.numbering;

import com.nexperia.qms.common.numbering.mapper.SequenceMapper;
import org.springframework.stereotype.Service;

/**
 * The single place that knows which prefix and sequence key each business
 * document uses. Only the complaint number has a rule mandated by the
 * requirements (C + 4-digit year + 5-digit sequence, Q-13); the others follow
 * the same shape with their own prefix so every identifier is self-describing.
 *
 * Call these inside the same transaction as the insert: the sequence row lock is
 * held until commit, and a number is only burned once the row actually lands.
 */
@Service
public class DocumentNumberService {

    private static final int WIDTH = 5;

    private final SequenceMapper sequenceMapper;

    public DocumentNumberService(SequenceMapper sequenceMapper) {
        this.sequenceMapper = sequenceMapper;
    }

    /** Complaint number, e.g. C202600722 (requirement 3.1.2 / Q-13). */
    public String nextComplaintId() {
        return sequenceMapper.next("C", "COMPLAINT", WIDTH);
    }

    public String nextSampleId() {
        return sequenceMapper.next("S", "SAMPLE", WIDTH);
    }

    public String nextShipmentId() {
        return sequenceMapper.next("SH", "SHIPMENT", WIDTH);
    }

    public String nextVerificationTaskId() {
        return sequenceMapper.next("VT", "VERIF", WIDTH);
    }

    public String nextContainmentActionId() {
        return sequenceMapper.next("CA", "CONTAIN", WIDTH);
    }

    public String nextRootCauseId() {
        return sequenceMapper.next("RC", "ROOTCAUSE", WIDTH);
    }

    public String nextCorrectiveActionId() {
        return sequenceMapper.next("PCA", "CORRACT", WIDTH);
    }

    public String nextReportId() {
        return sequenceMapper.next("R", "REPORT8D", WIDTH);
    }

    public String nextApprovalId() {
        return sequenceMapper.next("AP", "APPROVAL", WIDTH);
    }
}
