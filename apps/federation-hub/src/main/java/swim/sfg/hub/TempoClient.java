package swim.sfg.hub;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

import java.util.Map;

@RegisterRestClient(configKey = "tempo")
@Path("/api")
public interface TempoClient {

    @GET
    @Path("/traces/{traceId}")
    @Produces(MediaType.APPLICATION_JSON)
    Map<String, Object> getTrace(@PathParam("traceId") String traceId);
}
