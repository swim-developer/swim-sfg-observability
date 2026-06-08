using System.Text.Json.Serialization;

namespace DnotamConsumer;

public record NotamMessage(
    [property: JsonPropertyName("notam_id")] string? NotamId,
    [property: JsonPropertyName("aerodrome")] string? Aerodrome,
    [property: JsonPropertyName("notam_type")] string? NotamType,
    [property: JsonPropertyName("runway")] string? Runway
);
