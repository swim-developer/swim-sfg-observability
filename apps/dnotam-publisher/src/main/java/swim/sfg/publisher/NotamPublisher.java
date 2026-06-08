package swim.sfg.publisher;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.jboss.logging.MDC;

@Slf4j
@ApplicationScoped
public class NotamPublisher {

    @Inject
    @Channel("dnotam-out")
    Emitter<String> emitter;

    @Inject
    ObjectMapper mapper;

    private final Counter publishCounter;
    private final Counter publishErrorCounter;
    private final Timer publishTimer;

    @Inject
    public NotamPublisher(MeterRegistry registry) {
        publishCounter = Counter.builder("dnotam.publishes")
                .description("Number of DNOTAMs published to AMQP")
                .register(registry);
        publishErrorCounter = Counter.builder("dnotam.publish.errors")
                .description("Number of failed DNOTAM publish attempts")
                .register(registry);
        publishTimer = Timer.builder("dnotam.publish.duration")
                .description("Duration of DNOTAM publish operations")
                .register(registry);
    }

    public void publish(NotamRequest request, String traceparent) {
        publishTimer.record(() -> doPublish(request, traceparent));
    }

    private void doPublish(NotamRequest request, String traceparent) {
        Span span = Span.current();
        span.setAttribute("notam.id", request.notamId());
        span.setAttribute("notam.aerodrome", request.aerodrome());
        span.setAttribute("notam.type", request.notamType());
        span.setAttribute("notam.runway", request.runway());

        try {
            String payload = mapper.writeValueAsString(request);
            emitter.send(payload);
            publishCounter.increment();
            swimLog("OPERATIONAL_EVENT", "DNOTAM published to SWIM broker", request, traceparent);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            publishErrorCounter.increment();
            swimLog("BUSINESS_ALERT", "Failed to publish DNOTAM: " + e.getMessage(), request, traceparent);
        }
    }

    private void swimLog(String eventType, String message, NotamRequest notam, String traceparent) {
        try {
            MDC.put("swim_perimeter", "SERVICE_LAYER");
            MDC.put("event_type", eventType);
            MDC.put("notam.id", notam.notamId());
            MDC.put("notam.aerodrome", notam.aerodrome());
            MDC.put("notam.type", notam.notamType());
            MDC.put("notam.runway", notam.runway());
            MDC.put("service_context", "dNOTAM");
            MDC.put("traceparent", traceparent);
            log.info("[SERVICE_LAYER][{}] {} | notam_id={} aerodrome={} runway={} traceparent={}",
                    eventType, message, notam.notamId(), notam.aerodrome(), notam.runway(), traceparent);
        } finally {
            MDC.clear();
        }
    }
}
