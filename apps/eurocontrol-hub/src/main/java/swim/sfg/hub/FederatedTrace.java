package swim.sfg.hub;

import java.util.List;
import java.util.Set;

public record FederatedTrace(
        String traceId,
        Set<String> participants,
        List<Participant> spans,
        long totalDurationMicros
) {}
