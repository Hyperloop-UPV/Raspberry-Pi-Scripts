# Raspberry-Pi-Scripts

Scripts used in the Hyperloop-UPV Raspberry Pi gateway — configuration utilities and monitoring tools.

---

## Scripts

### `set-static-ip.sh`

Configures a static IP address for a given network interface.

```bash
sudo ./set-static-ip.sh <interface> <ip>/<prefix> <gateway>
# Example:
sudo ./set-static-ip.sh eth0 192.168.1.10/24 192.168.1.1
```

---

## `monitor/` — Gateway monitoring

Two files work together to capture and visualise the Pi's performance.

### `monitor/snapshot.sh` — Data collection

Takes a system snapshot by sampling metrics over a time window and appending a row to `snapshot.csv`.

```bash
./monitor/snapshot.sh [period_seconds] [interface]
```

| Argument         | Default | Description                                            |
|------------------|---------|--------------------------------------------------------|
| `period_seconds` | `5`     | Duration of the sampling window in seconds             |
| `interface`      | all     | Restrict network stats to one interface (e.g. `eth0`) |

**Examples:**

```bash
# Single snapshot, 5-second window, all interfaces
./monitor/snapshot.sh

# 10-second window
./monitor/snapshot.sh 10

# 10-second window, only eth0
./monitor/snapshot.sh 10 eth0

# Take 20 snapshots every 10 seconds (builds a time series)
for i in $(seq 20); do ./monitor/snapshot.sh 10; done
```

Each run prints a human-readable summary to the terminal and appends one row to `monitor/snapshot.csv`. The CSV header is written automatically on the first run.

**What it measures:**

| Metric | Description |
|--------|-------------|
| CPU usage % | Overall and broken down by user / sys / iowait / irq / softirq |
| CPU temperature | In °C — critical inside the vehicle enclosure |
| Throttle state | Whether the Pi has reduced its speed due to heat |
| RAM usage | Used and available, in MB and % |
| Network throughput | Bytes/s and packets/s per interface, RX and TX |
| Network drops | Packets discarded at the interface level |
| UDP packet rate | Packets/s in and out |
| UDP buffer errors | **Most critical** — packets dropped because the Pi could not process them fast enough |

---

### `monitor/report.Rmd` — PDF report

An R Markdown document that reads `snapshot.csv` and generates a PDF report with charts and plain-language explanations. Intended for sharing with non-technical team members.

**Requirements:**

```r
install.packages(c("rmarkdown", "tidyverse", "scales", "knitr"))
```

A LaTeX distribution is also required for PDF output. On a Debian-based system:

```bash
sudo apt install texlive-xetex texlive-fonts-recommended
```

**Generate the report:**

```bash
# Run from inside the monitor/ directory
Rscript -e "rmarkdown::render('report.Rmd')"
```

This produces `monitor/report.pdf`.

**Typical workflow:**

```bash
# 1. Collect data — e.g. 30 snapshots every 5 seconds during a test run
for i in $(seq 30); do ./monitor/snapshot.sh 5; done

# 2. Generate the report (copy snapshot.csv to your laptop first if needed)
Rscript -e "rmarkdown::render('monitor/report.Rmd')"
```

**Report contents:**

| Section | What it shows |
|---------|---------------|
| System Summary | Key figures at a glance |
| CPU — Usage breakdown | How processor time was spent |
| CPU — Temperature | Whether the Pi overheated |
| Memory | RAM headroom over time |
| Network (per interface) | Throughput and drops for each network port separately |
| UDP — Packet rate | Packets per second from the boards |
| UDP — Dropped packets | Data loss due to buffer overflow (most critical metric) |
