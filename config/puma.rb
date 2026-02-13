# This file is UMD-managed since upstream Avalon 7.x did not use Puma.
# We should reconcile with upstream during Avalon 8.x upgrade.
# Configure puma workers and threads based on CPU Limits
workers_count = ENV.fetch('PUMA_WORKERS', 2).to_i
workers workers_count
threads_count = ENV.fetch('RAILS_MAX_THREADS', 3).to_i
threads threads_count, threads_count
