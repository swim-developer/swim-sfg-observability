package swim.sfg.publisher;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.context.Context;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import lombok.extern.slf4j.Slf4j;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@Path("/v1/notam")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class NotamResource {

    @Inject
    OpenTelemetry openTelemetry;

    @Inject
    NotamPublisher publisher;

    @POST
    @Path("/publish")
    public Response publish(NotamRequest request) {
        if (request == null || !request.isComplete()) {
            return Response.status(400)
                    .entity(Map.of("error", "Missing required fields: notam_id, aerodrome, notam_type, runway"))
                    .build();
        }

        String traceparent = extractTraceparent();
        publisher.publish(request, traceparent);

        return Response.status(202)
                .entity(Map.of("status", "published", "traceparent", traceparent))
                .build();
    }

    private String extractTraceparent() {
        Map<String, String> carrier = new HashMap<>();
        openTelemetry.getPropagators()
                .getTextMapPropagator()
                .inject(Context.current(), carrier, Map::put);
        return carrier.getOrDefault("traceparent", "");
    }
}
