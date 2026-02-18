#!/bin/bash
#############################################################################
# Pipeline Configuration File
# Copy this file and modify as needed
#############################################################################

# Thread Settings
export THREADS=8                    # Number of threads for general processing
export SAMTOOLS_THREADS=4           # Threads for samtools operations

# Quality Filtering Thresholds
export MIN_QUALITY=20               # Minimum base quality for trimming
export MIN_LENGTH=50                # Minimum read length after trimming
export MIN_MQ=30                    # Minimum mapping quality for variants
export MIN_DP=5                     # Minimum read depth for variants
export MIN_AD=3                     # Minimum alternate allele depth

# Email Notifications (optional - requires mailx configured)
export SEND_EMAIL=false             # Set to true to enable email notifications
export EMAIL_ADDRESS=""             # Your email address

# Resume Settings
export CLEAN_RESUME=false           # Set to true to start fresh (ignore resume file)

# Advanced Settings
export KEEP_INTERMEDIATE=false      # Keep intermediate BAM files (SAM, unsorted BAM)
export PARALLEL_SAMPLES=false       # Process multiple samples in parallel (experimental)
export MAX_PARALLEL=3               # Maximum number of parallel sample processes
