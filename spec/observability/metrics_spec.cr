require "../spec_helper"

describe Altair::Observability::Metrics do
  it "counts requests, failures and cumulative durations" do
    metrics = Altair::Observability::Metrics.new
    metrics.record(200, 1.millisecond)
    metrics.record(503, 2.milliseconds)
    body = metrics.to_prometheus
    body.should contain "altair_http_requests_total 2"
    body.should contain "altair_http_server_errors_total 1"
    body.should contain "altair_http_request_duration_microseconds_total 3000"
  end

  it "can reset a process registry between tests" do
    metrics = Altair::Observability::Metrics.new
    metrics.record(200, 1.millisecond)
    metrics.reset!
    metrics.to_prometheus.should contain "altair_http_requests_total 0"
  end
end
