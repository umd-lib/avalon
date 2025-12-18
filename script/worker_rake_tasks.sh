#!/usr/bin/env bash

# Copyright 2011-2023, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

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

  # Cancel and requeue active encode jobs and exit, if sidekiq is not running
  if ! pgrep -f "sidekiq" > /dev/null; then
    echo "[periodic] Sidekiq not running, cancelling active encode jobs..."
    bundle exec rake umd:cancel_and_requeue_active_encode_jobs
    echo "[periodic] Exiting worker rake tasks script."
    exit 0
  fi

  echo "[periodic] Cleaning up local encode files older than ${older_than}..."
  bundle exec rake avalon:local_encode_cleanup

  echo "[periodic] Worker rake tasks completed at $(date). Sleeping for ${POLLING_INTERVAL} seconds."
  sleep "${POLLING_INTERVAL}"
done
