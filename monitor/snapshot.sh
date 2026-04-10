#!/bin/bash
# Snapshot system and network usage for the Hyperloop gateway Pi.
# Takes two samples separated by PERIOD seconds, reports deltas and rates.
#
# Usage: ./snapshot.sh [period_seconds] [interface]
#   period_seconds  — sampling window in seconds (default: 5)
#   interface       — limit to one NIC, e.g. eth0 (default: all)
#
# CSV is written to ./snapshot.csv alongside this script.

PERIOD=${1:-5}
IFACE=${2:-}
CSV_FILE="$(dirname "$0")/snapshot.csv"
SEP="─────────────────────────────────────────"

# ── Helpers ───────────────────────────────────────────────────────────────────

human_bytes() {
    awk "BEGIN {
        v=$1; split(\"B KB MB GB\", u)
        for(i=4;i>=1;i--) if(v>=2^(10*(i-1))) { printf \"%.1f %s\", v/2^(10*(i-1)), u[i]; break }
    }"
}

# Returns: rx_bytes rx_pkts rx_drops tx_bytes tx_pkts tx_drops
iface_counters() {
    local iface=$1
    ip -s link show "$iface" 2>/dev/null | awk '
        /RX:/ { getline; rx_b=$1; rx_p=$2; rx_d=$4 }
        /TX:/ { getline; tx_b=$1; tx_p=$2; tx_d=$4 }
        END   { print rx_b, rx_p, rx_d, tx_b, tx_p, tx_d }
    '
}

# Returns: udp_in no_port recv_err udp_out send_err
udp_counters() {
    awk '/^Udp:/{if(h){print $2,$3,$4,$5,$6} h=!h}' /proc/net/snmp
}

# Returns: user nice sys idle iowait irq softirq
cpu_counters() {
    awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8; exit}' /proc/stat
}

# ── Resolve interfaces ────────────────────────────────────────────────────────

IFACES=()
if [ -n "$IFACE" ]; then
    IFACES=("$IFACE")
else
    while IFS= read -r line; do
        IFACES+=("$line")
    done < <(ip -o link show | awk -F': ' '$2 !~ /^lo$/ {print $2}')
fi

# ── Sample 1 ──────────────────────────────────────────────────────────────────

echo "Sampling for ${PERIOD}s..."

T1=$(date '+%Y-%m-%d %H:%M:%S')

read -r cpu1_us cpu1_ni cpu1_sy cpu1_id cpu1_wa cpu1_irq cpu1_si <<< "$(cpu_counters)"
read -r udp1_in udp1_np udp1_re udp1_out udp1_se <<< "$(udp_counters)"

declare -A RX_B1 RX_P1 RX_D1 TX_B1 TX_P1 TX_D1
for iface in "${IFACES[@]}"; do
    read -r RX_B1[$iface] RX_P1[$iface] RX_D1[$iface] \
             TX_B1[$iface] TX_P1[$iface] TX_D1[$iface] <<< "$(iface_counters "$iface")"
done

sleep "$PERIOD"

# ── Sample 2 ──────────────────────────────────────────────────────────────────

T2=$(date '+%Y-%m-%d %H:%M:%S')

read -r cpu2_us cpu2_ni cpu2_sy cpu2_id cpu2_wa cpu2_irq cpu2_si <<< "$(cpu_counters)"
read -r udp2_in udp2_np udp2_re udp2_out udp2_se <<< "$(udp_counters)"

declare -A RX_B2 RX_P2 RX_D2 TX_B2 TX_P2 TX_D2
for iface in "${IFACES[@]}"; do
    read -r RX_B2[$iface] RX_P2[$iface] RX_D2[$iface] \
             TX_B2[$iface] TX_P2[$iface] TX_D2[$iface] <<< "$(iface_counters "$iface")"
done

# ── CPU deltas ────────────────────────────────────────────────────────────────

d_us=$(( cpu2_us  - cpu1_us  ))
d_ni=$(( cpu2_ni  - cpu1_ni  ))
d_sy=$(( cpu2_sy  - cpu1_sy  ))
d_id=$(( cpu2_id  - cpu1_id  ))
d_wa=$(( cpu2_wa  - cpu1_wa  ))
d_irq=$(( cpu2_irq - cpu1_irq ))
d_si=$(( cpu2_si  - cpu1_si  ))
cpu_total=$(( d_us + d_ni + d_sy + d_id + d_wa + d_irq + d_si ))

pct() { awk "BEGIN {printf \"%.1f\", $1*100/${cpu_total:-1}}"; }

CPU_USED=$(  pct $(( d_us + d_ni + d_sy )) )
CPU_USER=$(  pct "$d_us" )
CPU_SYS=$(   pct "$d_sy" )
CPU_IOWAIT=$(pct "$d_wa" )
CPU_IRQ=$(   pct "$d_irq" )
CPU_SOFTIRQ=$(pct "$d_si" )

# ── CPU temperature & throttle ────────────────────────────────────────────────

if command -v vcgencmd &>/dev/null; then
    CPU_TEMP=$(vcgencmd measure_temp | grep -oP '[0-9.]+')
    THROTTLED_RAW=$(vcgencmd get_throttled | cut -d= -f2)
    [ "$THROTTLED_RAW" = "0x0" ] && THROTTLED="no" || THROTTLED="YES($THROTTLED_RAW)"
elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    CPU_TEMP=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
    THROTTLED="N/A"
else
    CPU_TEMP="N/A"; THROTTLED="N/A"
fi

# ── RAM (instantaneous) ───────────────────────────────────────────────────────

RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
RAM_USED=$(  free -m | awk '/^Mem:/{print $3}')
RAM_AVAIL=$( free -m | awk '/^Mem:/{print $7}')
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
SWAP_USED=$( free -m | awk '/^Swap:/{print $3}')

RAM_USED_PCT=$( awk "BEGIN {printf \"%.1f\", ${RAM_USED}*100/${RAM_TOTAL:-1}}")
RAM_AVAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ${RAM_AVAIL}*100/${RAM_TOTAL:-1}}")
SWAP_USED_PCT=$(awk "BEGIN {printf \"%.1f\", ${SWAP_USED}*100/${SWAP_TOTAL:-1}}")

# ── UDP deltas ────────────────────────────────────────────────────────────────

D_UDP_IN=$(( udp2_in  - udp1_in  ))
D_UDP_NP=$(( udp2_np  - udp1_np  ))
D_UDP_RE=$(( udp2_re  - udp1_re  ))
D_UDP_OUT=$(( udp2_out - udp1_out ))
D_UDP_SE=$(( udp2_se  - udp1_se  ))
UDP_SOCKETS=$(ss -uanp 2>/dev/null | grep -c UNCONN)

rate() { awk "BEGIN {printf \"%.0f\", $1/${PERIOD}}"; }

# ── Human-readable output ─────────────────────────────────────────────────────

echo ""
echo "Hyperloop Gateway — ${PERIOD}s window  ($T1 → $T2)"
echo "Uptime: $(uptime -p)"
echo ""

echo "CPU  (average over ${PERIOD}s)"
echo "$SEP"
printf "  Temperature : %s°C\n" "$CPU_TEMP"
printf "  Throttled   : %s\n"   "$THROTTLED"
printf "  Total usage : %s%%\n" "$CPU_USED"
printf "  ├ user      : %s%%\n" "$CPU_USER"
printf "  ├ sys       : %s%%\n" "$CPU_SYS"
printf "  ├ iowait    : %s%%\n" "$CPU_IOWAIT"
printf "  ├ irq       : %s%%\n" "$CPU_IRQ"
printf "  └ softirq   : %s%%\n" "$CPU_SOFTIRQ"
echo ""

echo "Memory  (instantaneous)"
echo "$SEP"
printf "  RAM  — total: %sMB  used: %sMB (%s%%)  available: %sMB (%s%%)\n" \
    "$RAM_TOTAL" "$RAM_USED" "$RAM_USED_PCT" "$RAM_AVAIL" "$RAM_AVAIL_PCT"
printf "  Swap — total: %sMB  used: %sMB (%s%%)\n" "$SWAP_TOTAL" "$SWAP_USED" "$SWAP_USED_PCT"
echo ""

echo "Network interfaces  (delta over ${PERIOD}s)"
echo "$SEP"
iface_header_csv=""
iface_values_csv=""
for iface in "${IFACES[@]}"; do
    [ -z "${RX_B1[$iface]+x}" ] && continue

    d_rx_b=$(( RX_B2[$iface] - RX_B1[$iface] ))
    d_rx_p=$(( RX_P2[$iface] - RX_P1[$iface] ))
    d_rx_d=$(( RX_D2[$iface] - RX_D1[$iface] ))
    d_tx_b=$(( TX_B2[$iface] - TX_B1[$iface] ))
    d_tx_p=$(( TX_P2[$iface] - TX_P1[$iface] ))
    d_tx_d=$(( TX_D2[$iface] - TX_D1[$iface] ))

    rx_h=$(human_bytes "$d_rx_b")
    tx_h=$(human_bytes "$d_tx_b")
    rx_rate=$(human_bytes "$(rate "$d_rx_b")")
    tx_rate=$(human_bytes "$(rate "$d_tx_b")")

    printf "  %-12s  RX: %8s  (%s/s)  pkts: %s  drops: %s\n" \
        "$iface" "$rx_h" "$rx_rate" "$d_rx_p" "$d_rx_d"
    printf "  %-12s  TX: %8s  (%s/s)  pkts: %s  drops: %s\n" \
        ""       "$tx_h" "$tx_rate" "$d_tx_p" "$d_tx_d"

    iface_header_csv+=",${iface}_rx_bytes,${iface}_rx_pkts,${iface}_rx_drops,${iface}_rx_bytes_per_s,${iface}_tx_bytes,${iface}_tx_pkts,${iface}_tx_drops,${iface}_tx_bytes_per_s"
    iface_values_csv+=",$d_rx_b,$d_rx_p,$d_rx_d,$(rate "$d_rx_b"),$d_tx_b,$d_tx_p,$d_tx_d,$(rate "$d_tx_b")"
done
echo ""

echo "UDP statistics  (delta over ${PERIOD}s)"
echo "$SEP"
printf "  Packets in       : %s  (%s pkt/s)\n" "$D_UDP_IN"  "$(rate "$D_UDP_IN")"
printf "  Packets out      : %s  (%s pkt/s)\n" "$D_UDP_OUT" "$(rate "$D_UDP_OUT")"
printf "  No port errors   : %s\n"              "$D_UDP_NP"
printf "  Recv buf errors  : %s  ← packets dropped (full socket buffer)\n" "$D_UDP_RE"
printf "  Send buf errors  : %s\n"              "$D_UDP_SE"
printf "  Open UDP sockets : %s\n"              "$UDP_SOCKETS"
echo ""

echo "Top 5 processes by CPU"
echo "$SEP"
ps -eo pid,pcpu,pmem,comm --sort=-%cpu | head -6 | awk '
    NR==1 { printf "  %-7s %5s %5s  %s\n", $1, $2, $3, $4 }
    NR >1 { printf "  %-7s %4s%% %4s%%  %s\n", $1, $2, $3, $4 }
'
echo ""

# ── CSV output ────────────────────────────────────────────────────────────────

HEADER="timestamp_start,timestamp_end,period_s,cpu_temp_c,cpu_usage_pct,cpu_user_pct,cpu_sys_pct,cpu_iowait_pct,cpu_irq_pct,cpu_softirq_pct,throttled,ram_total_mb,ram_used_mb,ram_used_pct,ram_avail_mb,ram_avail_pct,swap_total_mb,swap_used_mb,swap_used_pct${iface_header_csv},udp_in_pkts,udp_in_pkt_per_s,udp_out_pkts,udp_out_pkt_per_s,udp_no_port_errors,udp_recv_buf_errors,udp_send_buf_errors,udp_open_sockets"
ROW="\"$T1\",\"$T2\",$PERIOD,$CPU_TEMP,$CPU_USED,$CPU_USER,$CPU_SYS,$CPU_IOWAIT,$CPU_IRQ,$CPU_SOFTIRQ,$THROTTLED,$RAM_TOTAL,$RAM_USED,$RAM_USED_PCT,$RAM_AVAIL,$RAM_AVAIL_PCT,$SWAP_TOTAL,$SWAP_USED,$SWAP_USED_PCT${iface_values_csv},$D_UDP_IN,$(rate "$D_UDP_IN"),$D_UDP_OUT,$(rate "$D_UDP_OUT"),$D_UDP_NP,$D_UDP_RE,$D_UDP_SE,$UDP_SOCKETS"

[ ! -f "$CSV_FILE" ] && echo "$HEADER" > "$CSV_FILE"
echo "$ROW" >> "$CSV_FILE"
echo "CSV row appended → $CSV_FILE"
