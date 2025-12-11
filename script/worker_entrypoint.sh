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

SIDEKIQ_PID=""

# Trap signals and forward them
trap 'handle_tstp' USR1

forward_signal() {
  echo "Received SIGUSR1, forwarding to Sidekiq..." >&2
  # Find the actual sidekiq process
  SIDEKIQ_PID=$(pgrep -f "sidekiq.*config/sidekiq.yml")
  if [ -n "$SIDEKIQ_PID" ]; then
    echo "Forwarding to PID: $SIDEKIQ_PID" >&2
    kill -USR1 "$SIDEKIQ_PID"
  else
    echo "Sidekiq process not found" >&2
  fi
}

trap 'forward_signal' USR1

# Start periodic script
/home/app/avalon/script/worker_rake_tasks.sh &

# Start Sidekiq
echo "Starting Sidekiq..."
exec bundle exec sidekiq -t "${SIDEKIQ_TERMINATION_GRACE_PERIOD:-1800}" -C config/sidekiq.yml
