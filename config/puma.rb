# Configure puma workers and threads based on CPU Limits
cpu_limit = (Integer(ENV['CPU_LIMIT_IN_M']) / 1000) || 2
# UMD Customization
workers_count = Integer(ENV['PUMA_WORKERS']) || cpu_limit
# End UMD Customization
workers workers_count
# UMD Customization
max_threads_count = Integer(ENV['PUMA_MAX_THREADS']) || cpu_limit * 8
min_threads_count = Integer(ENV['PUMA_MIN_THREADS']) || 8
# End UMD Customization
threads min_threads_count, max_threads_count
