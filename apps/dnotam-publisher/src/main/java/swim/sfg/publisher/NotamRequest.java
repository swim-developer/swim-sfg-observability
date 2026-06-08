package swim.sfg.publisher;

import com.fasterxml.jackson.annotation.JsonProperty;

public record NotamRequest(
        @JsonProperty("notam_id") String notamId,
        String aerodrome,
        @JsonProperty("notam_type") String notamType,
        String runway,
        @JsonProperty("effective_from") String effectiveFrom,
        @JsonProperty("effective_to") String effectiveTo
) {
    public boolean isComplete() {
        return notamId != null && aerodrome != null && notamType != null && runway != null;
    }
}
