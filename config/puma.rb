# Configure puma workers and threads based on CPU Limits
cpu_limit = (Integer(ENV['CPU_LIMIT_IN_M']) / 1000) || 2
workers cpu_limit
max_threads_count = cpu_limit * 8
min_threads_count = 8
threads min_threads_count, max_threads_count
