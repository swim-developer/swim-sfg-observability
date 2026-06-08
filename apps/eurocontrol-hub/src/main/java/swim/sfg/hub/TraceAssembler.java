package swim.sfg.hub;

import jakarta.enterprise.context.ApplicationScoped;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@ApplicationScoped
public class TraceAssembler {

    @SuppressWarnings("unchecked")
    FederatedTrace assemble(String traceId, Map<String, Object> tempoResponse) {
        List<Participant> participants = new ArrayList<>();
        Set<String> services = new LinkedHashSet<>();

        Object batchesRaw = tempoResponse.get("batches");
        if (!(batchesRaw instanceof List<?> batches)) {
            return new FederatedTrace(traceId, services, participants, 0L);
        }

        for (Object batchObj : batches) {
            if (!(batchObj instanceof Map<?, ?> batch)) continue;
            String service = extractServiceName((Map<String, Object>) batch);
            List<Map<String, Object>> spans = extractSpans((Map<String, Object>) batch);
            for (Map<String, Object> span : spans) {
                String operation = (String) span.getOrDefault("name", "unknown");
                String spanId = (String) span.getOrDefault("spanId", "");
                String parentSpanId = (String) span.getOrDefault("parentSpanId", "");
                long startNano = toLong(span.get("startTimeUnixNano"));
                long endNano = toLong(span.get("endTimeUnixNano"));
                long durationMicros = (endNano - startNano) / 1000L;
                boolean hasError = hasError((Map<String, Object>) span);
                services.add(service);
                participants.add(new Participant(
                        service,
                        operation,
                        spanId,
                        parentSpanId,
                        Instant.ofEpochSecond(0, startNano),
                        durationMicros,
                        hasError ? "ERROR" : "OK"
                ));
            }
        }

        long totalDuration = participants.stream()
                .mapToLong(Participant::durationMicros)
                .max()
                .orElse(0L);

        return new FederatedTrace(traceId, services, participants, totalDuration);
    }

    @SuppressWarnings("unchecked")
    private String extractServiceName(Map<String, Object> batch) {
        Object resource = batch.get("resource");
        if (!(resource instanceof Map<?, ?> r)) return "unknown";
        Object attrs = r.get("attributes");
        if (!(attrs instanceof List<?> list)) return "unknown";
        for (Object attr : list) {
            if (!(attr instanceof Map<?, ?> a)) continue;
            if ("service.name".equals(a.get("key"))) {
                Object val = ((Map<String, Object>) a).get("value");
                if (val instanceof Map<?, ?> v) {
                    Object sv = ((Map<String, Object>) v).get("stringValue");
                    if (sv instanceof String s) return s;
                }
            }
        }
        return "unknown";
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> extractSpans(Map<String, Object> batch) {
        List<Map<String, Object>> result = new ArrayList<>();
        Object scopeSpans = batch.get("scopeSpans");
        if (!(scopeSpans instanceof List<?> scopes)) return result;
        for (Object scopeObj : scopes) {
            if (!(scopeObj instanceof Map<?, ?> scope)) continue;
            Object spans = scope.get("spans");
            if (spans instanceof List<?> list) {
                for (Object span : list) {
                    if (span instanceof Map<?, ?> s) result.add((Map<String, Object>) s);
                }
            }
        }
        return result;
    }

    @SuppressWarnings("unchecked")
    private boolean hasError(Map<String, Object> span) {
        Object status = span.get("status");
        if (status instanceof Map<?, ?> s) {
            Object code = s.get("code");
            return "STATUS_CODE_ERROR".equals(code) || Integer.valueOf(2).equals(code);
        }
        return false;
    }

    private long toLong(Object value) {
        if (value instanceof Number n) return n.longValue();
        if (value instanceof String s) {
            try { return Long.parseLong(s); } catch (NumberFormatException ignored) {}
        }
        return 0L;
    }
}
