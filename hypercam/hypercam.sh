#!/bin/bash

source /home/hyperloop-upv/hypercam/config.env

ffmpeg \
  -f v4l2 \
  -input_format uyvy422 \
  -video_size 1280x720 \
  -framerate 30 \
  -i /dev/video0 \
  -c:v libx264 \
  -preset ultrafast \
  -tune zerolatency \
  -x264-params bframes=0:sync-lookahead=0:rc-lookahead=0 \
  -g 10 \
  -b:v 16M \
  -maxrate 16M \
  -bufsize 4M \
  -pix_fmt yuv420p \
  -f mpegts \
  "srt://${OBS_IP}:${OBS_PORT}?mode=caller&latency=${LATENCY}"
