using DnotamConsumer;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = Host.CreateApplicationBuilder(args);

var otlpEndpoint = builder.Configuration["OTLP_ENDPOINT"] ?? "http://tempo:4317";
var lokiEndpoint = builder.Configuration["LOKI_OTLP_ENDPOINT"] ?? "http://loki:3100/otlp/v1/logs";
var metricsPort = int.Parse(builder.Configuration["METRICS_PORT"] ?? "9464");
var resource = ResourceBuilder.CreateDefault()
    .AddService("dnotam-consumer", serviceVersion: "1.0.0", serviceNamespace: "swim-sfg")
    .AddAttributes([
        new("deployment.environment", builder.Configuration["DEPLOYMENT_ENV"] ?? "local"),
    ]);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resource)
        .AddSource("dnotam-consumer")
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpEndpoint);
            options.Protocol = OtlpExportProtocol.Grpc;
        }))
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resource)
        .AddMeter("dnotam-consumer")
        .AddPrometheusHttpListener(options =>
        {
            options.UriPrefixes = [$"http://*:{metricsPort}/"];
        }));

builder.Logging.SetMinimumLevel(LogLevel.Information);
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.SetResourceBuilder(resource);
    logging.IncludeScopes = true;
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(lokiEndpoint);
        options.Protocol = OtlpExportProtocol.HttpProtobuf;
    });
});

builder.Services.AddHostedService<AmqpConsumerService>();

await builder.Build().RunAsync();
