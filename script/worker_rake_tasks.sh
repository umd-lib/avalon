#!/bin/bash

# Define ffpmeg cleanup parameters
export older_than="${older_than:-1.days}"
export outputs="${older_than:-true}"

export POLLING_INTERVAL="${POLLING_INTERVAL:-60}"

while true; do
  echo "[periodic] Running worker_rake_tasks script at $(date)"
  cd /home/app/avalon || exit 2
  echo "[periodic] Processing running encodes..."
  bundle exec rake umd:process_running_encodes
  echo "[periodic] Cleaning up local encode files older than ${older_than}..."
  bundle exec rake avalon:local_encode_cleanup
  echo "[periodic] Worker rake tasks completed at $(date). Sleeping for ${POLLING_INTERVAL} seconds."
  sleep "${POLLING_INTERVAL}"
done