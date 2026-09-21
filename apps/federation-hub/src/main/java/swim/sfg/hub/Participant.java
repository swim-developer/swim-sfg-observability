package swim.sfg.hub;

import java.time.Instant;

public record Participant(
        String org,
        String service,
        String operation,
        String spanId,
        String parentSpanId,
        Instant startTime,
        long durationMicros,
        String status
) {}
