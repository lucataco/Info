# Privacy

Info is designed to be local-first.

## Default behavior

- CPU, GPU, memory, and network throughput are read from local macOS system APIs.
- Metric history is kept in memory only.
- Info does not create a metric database, analytics database, or log file.
- Info does not transmit data by default.

## Optional network features

These are disabled by default and only run while the Network detail panel is open:

- Public IP lookup calls `https://api.ipify.org` once per panel session.
- Connectivity latency sends a lightweight `HEAD` request to `https://captive.apple.com` every few seconds while visible.

## Optional temperature feature

Temperature is disabled by default and only runs while CPU/GPU detail panels are open. It reads local SMC keys and does not transmit data.

## Disk writes

Info stores preferences in `UserDefaults`. It does not write metric samples or history to disk.
