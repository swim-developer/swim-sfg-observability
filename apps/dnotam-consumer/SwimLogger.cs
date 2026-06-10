namespace DnotamConsumer;

public static class SwimLogger
{
    public static void OperationalEvent(ILogger logger, string message, NotamMessage? notam, string traceparent, string orgIcao = "") =>
        Log(logger, LogLevel.Information, "OPERATIONAL_EVENT", message, notam, traceparent, orgIcao);

    public static void ValidationFailure(ILogger logger, string message, NotamMessage? notam, string traceparent, string orgIcao = "") =>
        Log(logger, LogLevel.Warning, "VALIDATION_FAILURE", message, notam, traceparent, orgIcao);

    private static void Log(ILogger logger, LogLevel level, string eventType, string message, NotamMessage? notam, string traceparent, string orgIcao)
    {
        logger.Log(level,
            "[{SwimPerimeter}][{EventType}] {Message} | notam_id={NotamId} aerodrome={Aerodrome} runway={Runway} org_icao={OrgIcao} service_context={ServiceContext} traceparent={Traceparent}",
            "SERVICE_LAYER", eventType, message,
            notam?.NotamId ?? "", notam?.Aerodrome ?? "", notam?.Runway ?? "",
            orgIcao, "dNOTAM", traceparent);
    }
}
