# Example: `erpnext-dev dashboard --json`

Abbreviated sample from a healthy native host (fields omitted for brevity).
Full snapshots also include protection, healing dry-run, and monitoring paths.

```bash
sudo erpnext-dev dashboard --json
# or: sudo erpnext-dev health-snapshot
```

```json
{
  "schema_version": "1",
  "overall_status": "HEALTHY",
  "timestamp": "2026-07-17T00:10:00Z",
  "deployment": {
    "engine": "native",
    "engine_label": "Native (VM)",
    "site": "erp.example.com",
    "install_state": "Installed",
    "runtime_state": "Running",
    "toolkit_version": "1.17.2"
  },
  "resources": {
    "status": "HEALTHY",
    "disk_percent": 42,
    "inode_percent": 11,
    "memory_available_percent": 55,
    "swap_percent": 0,
    "load1": "0.21",
    "cpu_cores": 4,
    "cpu_percent": 12,
    "iowait_percent": 1
  },
  "application": {
    "status": "HEALTHY",
    "http": "HEALTHY",
    "http_detail": "HTTP 200 in 48ms",
    "http_latency_ms": 48,
    "workers": "HEALTHY",
    "scheduler": "HEALTHY",
    "queue": "HEALTHY",
    "queue_depth": 0
  },
  "healing": {
    "mode": "monitor",
    "state": "observing",
    "would_heal": "none",
    "http_fail_streak": 0,
    "overall_fail_streak": 0
  },
  "monitoring": {
    "history_file": "/var/lib/erpnext-dev/metrics/history.jsonl",
    "incidents_dir": "/var/lib/erpnext-dev/incidents"
  }
}
```

Related CLI:

```bash
sudo erpnext-dev incidents
sudo erpnext-dev health-history 20
sudo erpnext-dev health-metrics
```
