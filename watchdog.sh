#!/bin/bash
# Agent OS Builder watchdog — 自動重啟
cd /home/ymchang/agentos-builder
while true; do
  echo "[$(date)] Starting server..."
  node server.js 2>&1 | head -1
  echo "[$(date)] Server died, restarting in 3s..."
  sleep 3
done
