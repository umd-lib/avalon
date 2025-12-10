#!/bin/bash
set -e

# Start periodic script
/home/app/avalon/script/worker_rake_tasks.sh &

# Start Sidekiq
echo "Starting Sidekiq..."

bundle exec sidekiq -t "${SIDEKIQ_TERMINATION_GRACE_PERIOD:-1800}" -C config/sidekiq.yml &

# Wait for either process to exit
wait -n

# Exit with status of the first process that exits
exit $?
