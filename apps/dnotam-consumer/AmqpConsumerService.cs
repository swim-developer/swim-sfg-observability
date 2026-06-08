using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Amqp;
using OpenTelemetry.Context.Propagation;

namespace DnotamConsumer;

public partial class AmqpConsumerService : BackgroundService
{
    private static readonly ActivitySource ActivitySource = new("dnotam-consumer");
    private static readonly TextMapPropagator Propagator = Propagators.DefaultTextMapPropagator;

    private static readonly Meter ServiceMeter = new("dnotam-consumer", "1.0.0");
    private static readonly Counter<long> MessagesConsumed = ServiceMeter.CreateCounter<long>(
        "dnotam.messages.consumed", "1", "Number of AMQP messages consumed");
    private static readonly Counter<long> ValidationFailures = ServiceMeter.CreateCounter<long>(
        "dnotam.validation.failures", "1", "Number of messages that failed validation");
    private static readonly Histogram<double> ProcessingDuration = ServiceMeter.CreateHistogram<double>(
        "dnotam.processing.duration", "ms", "Duration of message processing");

    private readonly ILogger<AmqpConsumerService> _logger;
    private readonly string _host;
    private readonly int _port;
    private readonly string _user;
    private readonly string _password;

    private static readonly TimeSpan InitialReconnectDelay = TimeSpan.FromSeconds(2);

    public AmqpConsumerService(ILogger<AmqpConsumerService> logger, IConfiguration configuration)
    {
        _logger = logger;
        _host = configuration["AMQP_HOST"] ?? "artemis";
        _port = int.Parse(configuration["AMQP_PORT"] ?? "5672");
        _user = configuration["AMQP_USER"] ?? "admin";
        _password = configuration["AMQP_PASSWORD"] ?? "admin";
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var delay = InitialReconnectDelay;
        var attempt = 0;

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (attempt > 0)
                    _logger.LogInformation("Reconnect attempt {Attempt} — connecting to {Host}:{Port}", attempt, _host, _port);

                await ConsumeLoop(stoppingToken);

                delay = InitialReconnectDelay;
                attempt = 0;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                attempt++;
                _logger.LogError(ex, "AMQP connection failed (attempt {Attempt}), retrying in {Delay}s", attempt, (int)delay.TotalSeconds);
                try
                {
                    await Task.Delay(delay, stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, 60));
            }
        }
    }

    private async Task ConsumeLoop(CancellationToken stoppingToken)
    {
        var address = new Address($"amqp://{_user}:{_password}@{_host}:{_port}");
        var connection = await Connection.Factory.CreateAsync(address);
        var session = new Session(connection);
        var receiver = new ReceiverLink(session, "dnotam-consumer", "swim.dnotam.updates");

        _logger.LogInformation("Connected to AMQP broker at {Host}:{Port}", _host, _port);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var message = await receiver.ReceiveAsync(TimeSpan.FromSeconds(5));
                if (message is null) continue;

                try
                {
                    ProcessMessage(message);
                    receiver.Accept(message);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to process message");
                    receiver.Reject(message);
                }
            }
        }
        finally
        {
            await receiver.CloseAsync();
            await session.CloseAsync();
            await connection.CloseAsync();
        }
    }

    private void ProcessMessage(Message message)
    {
        var startTimestamp = Stopwatch.GetTimestamp();
        var (traceparent, tracestate) = ExtractTraceContext(message);

        if (string.IsNullOrEmpty(traceparent))
            _logger.LogWarning("AMQP message received without traceparent in Application Properties — trace context will be broken");

        var carrier = new Dictionary<string, string> { ["traceparent"] = traceparent };
        if (!string.IsNullOrEmpty(tracestate))
            carrier["tracestate"] = tracestate;

        var parentContext = Propagator.Extract(default, carrier,
            (c, key) => c.TryGetValue(key, out var value) ? [value] : []);

        var json = message.Body switch
        {
            string s => s,
            byte[] b => Encoding.UTF8.GetString(b),
            _ => message.Body?.ToString() ?? "{}"
        };

        var notam = JsonSerializer.Deserialize<NotamMessage>(json);

        using var activity = ActivitySource.StartActivity("dnotam.process", ActivityKind.Consumer, parentContext.ActivityContext);
        activity?.SetTag("notam.id", notam?.NotamId);
        activity?.SetTag("notam.aerodrome", notam?.Aerodrome);
        activity?.SetTag("notam.type", notam?.NotamType);
        activity?.SetTag("notam.runway", notam?.Runway);
        activity?.SetTag("messaging.system", "amqp");
        activity?.SetTag("messaging.destination.name", "swim.dnotam.updates");

        MessagesConsumed.Add(1,
            new KeyValuePair<string, object?>("notam.aerodrome", notam?.Aerodrome),
            new KeyValuePair<string, object?>("notam.type", notam?.NotamType));

        if (!IsValidRunway(notam?.Runway))
        {
            activity?.SetStatus(ActivityStatusCode.Error, "Invalid runway code");
            ValidationFailures.Add(1,
                new KeyValuePair<string, object?>("notam.aerodrome", notam?.Aerodrome));
            SwimLogger.ValidationFailure(_logger, $"Invalid runway code '{notam?.Runway}' for aerodrome {notam?.Aerodrome}", notam, traceparent);
        }
        else
        {
            SwimLogger.OperationalEvent(_logger, $"DNOTAM integrated for flight operation at {notam?.Aerodrome}", notam, traceparent);
        }

        var elapsedMs = Stopwatch.GetElapsedTime(startTimestamp).TotalMilliseconds;
        ProcessingDuration.Record(elapsedMs,
            new KeyValuePair<string, object?>("notam.type", notam?.NotamType));
    }

    private static (string traceparent, string tracestate) ExtractTraceContext(Message message)
    {
        var traceparent = "";
        var tracestate = "";

        if (message.ApplicationProperties?.Map.TryGetValue("traceparent", out var tp) == true)
            traceparent = tp?.ToString() ?? "";

        if (message.ApplicationProperties?.Map.TryGetValue("tracestate", out var ts) == true)
            tracestate = ts?.ToString() ?? "";

        return (traceparent, tracestate);
    }

    [GeneratedRegex(@"^\d{2}[LRC]?$")]
    private static partial Regex RunwayPattern();

    private static bool IsValidRunway(string? runway) =>
        runway is not null && RunwayPattern().IsMatch(runway);
}
