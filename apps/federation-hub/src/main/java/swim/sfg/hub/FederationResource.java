package swim.sfg.hub;

import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.microprofile.rest.client.inject.RestClient;

import java.util.Map;
import java.util.Set;

@Slf4j
@Path("/v1/federation")
@Produces(MediaType.APPLICATION_JSON)
public class FederationResource {

    @Inject
    @RestClient
    TempoClient tempo;

    @Inject
    TraceAssembler assembler;

    @GET
    @Path("/traces/{traceId}")
    public FederatedTrace getTrace(@PathParam("traceId") String traceId) {
        log.info("Federation query for traceId={}", traceId);
        Map<String, Object> raw = tempo.getTrace(traceId);
        FederatedTrace trace = assembler.assemble(traceId, raw);
        if (trace.spans().isEmpty()) throw new NotFoundException("Trace not found: " + traceId);
        return trace;
    }

    @GET
    @Path("/participants/{traceId}")
    public Set<String> getParticipants(@PathParam("traceId") String traceId) {
        log.info("Participants query for traceId={}", traceId);
        Map<String, Object> raw = tempo.getTrace(traceId);
        FederatedTrace trace = assembler.assemble(traceId, raw);
        if (trace.participants().isEmpty()) throw new NotFoundException("Trace not found: " + traceId);
        return trace.participants();
    }
}
