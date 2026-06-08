namespace DnotamConsumer;

public static class SwimLogger
{
    public static void OperationalEvent(ILogger logger, string message, NotamMessage? notam, string traceparent) =>
        Log(logger, LogLevel.Information, "OPERATIONAL_EVENT", message, notam, traceparent);

    public static void ValidationFailure(ILogger logger, string message, NotamMessage? notam, string traceparent) =>
        Log(logger, LogLevel.Warning, "VALIDATION_FAILURE", message, notam, traceparent);

    private static void Log(ILogger logger, LogLevel level, string eventType, string message, NotamMessage? notam, string traceparent)
    {
        logger.Log(level,
            "[{SwimPerimeter}][{EventType}] {Message} | notam_id={NotamId} aerodrome={Aerodrome} runway={Runway} service_context={ServiceContext} traceparent={Traceparent}",
            "SERVICE_LAYER", eventType, message,
            notam?.NotamId ?? "", notam?.Aerodrome ?? "", notam?.Runway ?? "",
            "dNOTAM", traceparent);
    }
}
