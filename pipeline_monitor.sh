#!/bin/bash
#############################################################################
# Pipeline Monitor and Troubleshooting Tool
# Check pipeline status, view logs, and diagnose issues
#############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}âœ“ $1${NC}"
}

print_error() {
    echo -e "${RED}âœ— $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}âš  $1${NC}"
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local deps=(prefetch fasterq-dump pigz fastqc fastp bwa samtools picard bcftools bgzip tabix snpEff SnpSift qualimap multiqc curl unzip python3)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_success "$dep found"
        else
            print_error "$dep NOT FOUND"
            missing+=("$dep")
        fi
    done
    
    echo ""
    if [ ${#missing[@]} -eq 0 ]; then
        print_success "All dependencies are installed"
    else
        print_error "Missing dependencies: ${missing[*]}"
        echo "Install missing tools before running the pipeline"
    fi
}

check_disk_space() {
    print_header "Disk Space Analysis"
    
    df -h . | tail -1 | awk '{
        print "Available: " $4
        print "Used: " $3 " (" $5 ")"
    }'
    
    local available=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    
    echo ""
    if [ "$available" -lt 50 ]; then
        print_warn "Low disk space! NGS analysis requires significant storage"
        print_warn "Recommended: >100GB free space"
    else
        print_success "Sufficient disk space available"
    fi
}

check_directory_structure() {
    print_header "Directory Structure"
    
    local dirs=(
        "fastq/rawdata"
        "fastq/trimmed"
        "index"
        "results/aligned_bam"
        "results/sorted_bam"
        "results/dedup_bam"
        "results/pileup"
        "results/variant_vcf"
        "results/filtered_vcf"
        "results/annotation"
        "results/drug_resistance"
        "reports"
        "logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local count=$(find "$dir" -type f 2>/dev/null | wc -l)
            print_success "$dir ($count files)"
        else
            print_warn "$dir does not exist"
        fi
    done
}

view_latest_log() {
    print_header "Latest Pipeline Log (last 50 lines)"
    
    if ls logs/pipeline_*.log 1> /dev/null 2>&1; then
        local latest=$(ls -t logs/pipeline_*.log | head -1)
        echo "Log file: $latest"
        echo ""
        tail -50 "$latest"
    else
        print_warn "No log files found"
    fi
}

check_errors() {
    print_header "Recent Errors"
    
    if ls logs/error_*.log 1> /dev/null 2>&1; then
        local latest=$(ls -t logs/error_*.log | head -1)
        
        if [ -s "$latest" ]; then
            echo "Error log: $latest"
            echo ""
            cat "$latest"
        else
            print_success "No errors found in latest run"
        fi
    else
        print_success "No error logs found"
    fi
}

check_samples_progress() {
    print_header "Sample Processing Progress"
    
    if [ ! -f ".pipeline_resume" ]; then
        print_warn "No resume file found - pipeline may not have started"
        return
    fi
    
    echo "Completed steps:"
    cat .pipeline_resume | sort | uniq
    echo ""
    
    # Count samples at each stage
    local raw=$(ls fastq/rawdata/*.fastq.gz 2>/dev/null | wc -l)
    local trimmed=$(ls fastq/trimmed/*.fastq.gz 2>/dev/null | wc -l)
    local aligned=$(ls results/aligned_bam/*.bam 2>/dev/null | wc -l)
    local dedup=$(ls results/dedup_bam/*.bam 2>/dev/null | wc -l)
    local vcf=$(ls results/filtered_vcf/*.vcf.gz 2>/dev/null | wc -l)
    
    echo "Pipeline Stage Summary:"
    echo "  Raw FASTQ files: $raw"
    echo "  Trimmed reads: $trimmed"
    echo "  Aligned BAMs: $aligned"
    echo "  Deduplicated BAMs: $dedup"
    echo "  Filtered VCFs: $vcf"
}

check_results_summary() {
    print_header "Results Summary"
    
    # Variant count
    if ls results/filtered_vcf/*.vcf.gz 1> /dev/null 2>&1; then
        echo "Variants per sample:"
        for vcf in results/filtered_vcf/*.vcf.gz; do
            local sample=$(basename "$vcf" _filter.vcf.gz)
            local count=$(bcftools view -H "$vcf" 2>/dev/null | wc -l)
            echo "  $sample: $count variants"
        done
        echo ""
    fi
    
    # Drug resistance
    if [ -f "results/drug_resistance/resistance_mutations.tsv" ]; then
        local res_count=$(tail -n +2 results/drug_resistance/resistance_mutations.tsv 2>/dev/null | wc -l)
        if [ "$res_count" -gt 0 ]; then
            print_warn "Drug resistance mutations detected: $res_count"
            echo "See: results/drug_resistance/resistance_summary.txt"
        else
            print_success "No known drug resistance mutations detected"
        fi
    fi
    
    # Quality reports
    if ls reports/*.html 1> /dev/null 2>&1; then
        echo ""
        echo "Quality Control Reports:"
        ls -lh reports/*.html | awk '{print "  " $9 " (" $5 ")"}'
    fi
}

show_resource_usage() {
    print_header "Current Resource Usage"
    
    echo "CPU:"
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "  " 100 - $1"% used"}'
    
    echo ""
    echo "Memory:"
    free -h | awk 'NR==2{printf "  Total: %s\n  Used: %s (%.2f%%)\n  Free: %s\n", $2,$3,$3*100/$2,$4}'
    
    echo ""
    echo "Top processes:"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "  %-20s %5s%% CPU  %5s%% MEM\n", substr($11,1,20), $3, $4}'
}

clean_intermediate_files() {
    print_header "Cleaning Intermediate Files"
    
    echo "This will remove:"
    echo "  - SAM files (if any)"
    echo "  - Unsorted BAM files"
    echo "  - Uncompressed VCF files"
    echo "  - Temporary files"
    echo ""
    
    read -p "Continue? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        # Remove SAM files
        find results/aligned_bam -name "*.sam" -delete 2>/dev/null && print_success "Removed SAM files" || true
        
        # Remove intermediate files from index
        rm -rf index/ncbi_dataset 2>/dev/null && print_success "Removed NCBI dataset folder" || true
        rm -f index/genome.zip 2>/dev/null && print_success "Removed genome zip" || true
        
        # Calculate space saved
        echo ""
        print_success "Cleanup complete"
        df -h . | tail -1 | awk '{print "Current free space: " $4}'
    else
        echo "Cleanup cancelled"
    fi
}

show_menu() {
    clear
    echo "========================================="
    echo "  M. leprae Pipeline Monitor"
    echo "========================================="
    echo ""
    echo "1. Check dependencies"
    echo "2. Check disk space"
    echo "3. View directory structure"
    echo "4. View latest log"
    echo "5. Check for errors"
    echo "6. Check sample progress"
    echo "7. View results summary"
    echo "8. Show resource usage"
    echo "9. Clean intermediate files"
    echo "10. Full system check"
    echo "0. Exit"
    echo ""
}

full_check() {
    check_dependencies
    echo ""
    check_disk_space
    echo ""
    check_directory_structure
    echo ""
    check_samples_progress
    echo ""
    check_results_summary
    echo ""
    check_errors
}

# Main menu loop
if [ "$#" -eq 0 ]; then
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1) check_dependencies ;;
            2) check_disk_space ;;
            3) check_directory_structure ;;
            4) view_latest_log ;;
            5) check_errors ;;
            6) check_samples_progress ;;
            7) check_results_summary ;;
            8) show_resource_usage ;;
            9) clean_intermediate_files ;;
            10) full_check ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
else
    # Command line arguments
    case "$1" in
        --check-all) full_check ;;
        --dependencies) check_dependencies ;;
        --disk) check_disk_space ;;
        --progress) check_samples_progress ;;
        --errors) check_errors ;;
        --results) check_results_summary ;;
        --log) view_latest_log ;;
        *)
            echo "Usage: $0 [--check-all|--dependencies|--disk|--progress|--errors|--results|--log]"
            echo "  Or run without arguments for interactive menu"
            ;;
    esac
fi
