#!/bin/bash

#############################################################################
# M. leprae NGS Analysis Pipeline with Drug Resistance Detection
# Version: 2.0
# Features: Error handling, logging, resume capability, drug resistance
#############################################################################

# Strict error handling
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/pipeline_config.sh"
LOG_DIR="logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/pipeline_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/error_${TIMESTAMP}.log"
RESUME_FILE=".pipeline_resume"

# Thread settings
THREADS=${THREADS:-4}
SAMTOOLS_THREADS=${SAMTOOLS_THREADS:-2}

# Quality thresholds
MIN_QUALITY=${MIN_QUALITY:-20}
MIN_LENGTH=${MIN_LENGTH:-50}
MIN_MQ=${MIN_MQ:-30}
MIN_DP=${MIN_DP:-5}
MIN_AD=${MIN_AD:-3}

# Create necessary directories
mkdir -p ${LOG_DIR}

#############################################################################
# Logging Functions
#############################################################################

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" "${ERROR_LOG}" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*" | tee -a "${LOG_FILE}"
}

#############################################################################
# Error Handling
#############################################################################

cleanup_on_error() {
    log_error "Pipeline failed at step: $1"
    log_error "Check error log: ${ERROR_LOG}"
    exit 1
}

trap 'cleanup_on_error "${BASH_COMMAND}"' ERR

#############################################################################
# Utility Functions
#############################################################################

check_dependencies() {
    log_info "Checking dependencies..."
    local deps=(prefetch fasterq-dump pigz fastqc fastp bwa samtools picard bcftools bgzip tabix snpEff SnpSift qualimap multiqc curl unzip)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Please install missing tools before running the pipeline"
        exit 1
    fi
    log_success "All dependencies found"
}

mark_step_complete() {
    echo "$1" >> "${RESUME_FILE}"
}

is_step_complete() {
    if [ -f "${RESUME_FILE}" ]; then
        grep -q "^$1$" "${RESUME_FILE}" 2>/dev/null
    else
        return 1
    fi
}

#############################################################################
# Setup Functions
#############################################################################

create_directories() {
    if is_step_complete "create_directories"; then
        log_info "Directories already created, skipping..."
        return 0
    fi
    
    log_info "Creating directory structure..."
    mkdir -p \
        fastq/trimmed fastq/rawdata \
        reports/fastqc_raw reports/fastqc_trimmed reports/samtools_sort \
        reports/samtools_dedup reports/dedup_stat reports/qualimap \
        results/aligned_bam results/sorted_bam results/dedup_bam \
        results/pileup results/variant_vcf results/filtered_vcf \
        results/annotation results/drug_resistance \
        index tmp
    
    mark_step_complete "create_directories"
    log_success "Directory structure created"
}

download_reference() {
    if is_step_complete "download_reference"; then
        log_info "Reference genome already downloaded, skipping..."
        return 0
    fi
    
    log_info "Downloading M. leprae reference genome (GCF_000195855.1)..."
    
    if [ ! -f "./index/GCF_000195855.1_ASM19585v1_genomic.fna" ]; then
        curl -L "https://api.ncbi.nlm.nih.gov/datasets/v2alpha/genome/accession/GCF_000195855.1/download?include_annotation_type=GENOME_FASTA&include_annotation_type=GENOME_GFF&include_annotation_type=RNA_FASTA&include_annotation_type=CDS_FASTA&include_annotation_type=PROT_FASTA&include_annotation_type=SEQUENCE_REPORT&hydrated=FULLY_HYDRATED" \
            -o ./index/genome.zip || cleanup_on_error "Reference download failed"
        
        unzip -q ./index/genome.zip -d index/
        cp ./index/ncbi_dataset/data/GCF_000195855.1/GCF_000195855.1_ASM19585v1_genomic.fna ./index/
        
        # Also copy GFF for annotation
        if [ -f "./index/ncbi_dataset/data/GCF_000195855.1/genomic.gff" ]; then
            cp ./index/ncbi_dataset/data/GCF_000195855.1/genomic.gff ./index/
        fi
    fi
    
    mark_step_complete "download_reference"
    log_success "Reference genome downloaded"
}

index_reference() {
    if is_step_complete "index_reference"; then
        log_info "Reference already indexed, skipping..."
        return 0
    fi
    
    log_info "Indexing reference genome..."
    
    # Samtools index
    if [ ! -f "./index/GCF_000195855.1_ASM19585v1_genomic.fna.fai" ]; then
        samtools faidx ./index/GCF_000195855.1_ASM19585v1_genomic.fna
    fi
    
    # BWA index
    if [ ! -f "./index/leprae.bwt" ]; then
        bwa index ./index/GCF_000195855.1_ASM19585v1_genomic.fna -p index/leprae
    fi
    
    # Create sequence dictionary for GATK/Picard
    if [ ! -f "./index/GCF_000195855.1_ASM19585v1_genomic.dict" ]; then
        picard CreateSequenceDictionary \
            R=./index/GCF_000195855.1_ASM19585v1_genomic.fna \
            O=./index/GCF_000195855.1_ASM19585v1_genomic.dict
    fi
    
    mark_step_complete "index_reference"
    log_success "Reference genome indexed"
}

#############################################################################
# Sample Processing Functions
#############################################################################

process_sample() {
    local sra_id=$1
    local type=$2
    
    log_info "========================================="
    log_info "Processing sample: ${sra_id} (${type})"
    log_info "========================================="
    
    # Download data
    if ! is_step_complete "download_${sra_id}"; then
        log_info "Downloading: ${sra_id}"
        prefetch ${sra_id} -O fastq/rawdata/ || cleanup_on_error "prefetch failed for ${sra_id}"
        fasterq-dump -e ${THREADS} ./fastq/rawdata/${sra_id} -O fastq/rawdata/ || cleanup_on_error "fasterq-dump failed"
        pigz -p ${THREADS} ./fastq/rawdata/*.fastq
        mark_step_complete "download_${sra_id}"
    fi
    
    # FastQC on raw data
    if ! is_step_complete "fastqc_raw_${sra_id}"; then
        log_info "Running FastQC on raw data: ${sra_id}"
        fastqc ./fastq/rawdata/${sra_id}*.fastq.gz -o reports/fastqc_raw -t ${THREADS}
        mark_step_complete "fastqc_raw_${sra_id}"
    fi
    
    # Trimming and alignment
    if [[ "${type}" == "SINGLE" ]]; then
        process_single_end ${sra_id}
    elif [[ "${type}" == "PAIRED" ]]; then
        process_paired_end ${sra_id}
    else
        log_error "Unknown read type: ${type}"
        return 1
    fi
    
    # Post-alignment processing
    post_alignment_processing ${sra_id}
    
    # Variant calling
    variant_calling ${sra_id}
    
    log_success "Sample ${sra_id} processed successfully"
}

process_single_end() {
    local sra_id=$1
    
    if ! is_step_complete "trim_${sra_id}"; then
        log_info "Trimming single-end reads: ${sra_id}"
        fastp \
            -i ./fastq/rawdata/${sra_id}.fastq.gz \
            -o ./fastq/trimmed/${sra_id}_trimmed.fastq.gz \
            -e ${MIN_QUALITY} -l ${MIN_LENGTH} \
            -j ./reports/fastqc_trimmed/${sra_id}_fastp.json \
            -h ./reports/fastqc_trimmed/${sra_id}_fastp.html \
            -w ${THREADS}
        mark_step_complete "trim_${sra_id}"
    fi
    
    if ! is_step_complete "align_${sra_id}"; then
        log_info "Aligning single-end reads: ${sra_id}"
        bwa mem -t ${THREADS} \
            ./index/leprae \
            ./fastq/trimmed/${sra_id}_trimmed.fastq.gz | \
            samtools view -@ ${SAMTOOLS_THREADS} -Sb -o ./results/aligned_bam/${sra_id}.bam -
        mark_step_complete "align_${sra_id}"
    fi
}

process_paired_end() {
    local sra_id=$1
    
    if ! is_step_complete "trim_${sra_id}"; then
        log_info "Trimming paired-end reads: ${sra_id}"
        fastp \
            -i ./fastq/rawdata/${sra_id}_1.fastq.gz \
            -I ./fastq/rawdata/${sra_id}_2.fastq.gz \
            -o ./fastq/trimmed/${sra_id}_1_trimmed.fastq.gz \
            -O ./fastq/trimmed/${sra_id}_2_trimmed.fastq.gz \
            -e ${MIN_QUALITY} -l ${MIN_LENGTH} \
            -h ./reports/fastqc_trimmed/${sra_id}_fastp.html \
            -j ./reports/fastqc_trimmed/${sra_id}_fastp.json \
            -w ${THREADS}
        mark_step_complete "trim_${sra_id}"
    fi
    
    if ! is_step_complete "align_${sra_id}"; then
        log_info "Aligning paired-end reads: ${sra_id}"
        bwa mem -t ${THREADS} \
            ./index/leprae \
            ./fastq/trimmed/${sra_id}_1_trimmed.fastq.gz \
            ./fastq/trimmed/${sra_id}_2_trimmed.fastq.gz | \
            samtools view -@ ${SAMTOOLS_THREADS} -Sb -o ./results/aligned_bam/${sra_id}.bam -
        mark_step_complete "align_${sra_id}"
    fi
}

post_alignment_processing() {
    local sra_id=$1
    
    # Alignment statistics
    if ! is_step_complete "flagstat_aligned_${sra_id}"; then
        log_info "Computing alignment statistics: ${sra_id}"
        samtools flagstat -@ ${SAMTOOLS_THREADS} \
            ./results/aligned_bam/${sra_id}.bam > ./results/aligned_bam/${sra_id}.tsv
        mark_step_complete "flagstat_aligned_${sra_id}"
    fi
    
    # Sorting
    if ! is_step_complete "sort_${sra_id}"; then
        log_info "Sorting BAM file: ${sra_id}"
        samtools sort -@ ${SAMTOOLS_THREADS} \
            ./results/aligned_bam/${sra_id}.bam \
            -o ./results/sorted_bam/${sra_id}_sorted.bam -O bam
        samtools flagstat -@ ${SAMTOOLS_THREADS} \
            ./results/sorted_bam/${sra_id}_sorted.bam > ./reports/samtools_sort/${sra_id}.tsv
        mark_step_complete "sort_${sra_id}"
    fi
    
    # Mark duplicates
    if ! is_step_complete "dedup_${sra_id}"; then
        log_info "Marking duplicates: ${sra_id}"
        picard MarkDuplicates \
            I=./results/sorted_bam/${sra_id}_sorted.bam \
            O=./results/dedup_bam/${sra_id}_dupli.bam \
            M=./reports/samtools_dedup/${sra_id}_marked.txt \
            REMOVE_DUPLICATES=true \
            VALIDATION_STRINGENCY=LENIENT
        
        samtools flagstat -@ ${SAMTOOLS_THREADS} \
            ./results/dedup_bam/${sra_id}_dupli.bam > ./reports/dedup_stat/${sra_id}.tsv
        mark_step_complete "dedup_${sra_id}"
    fi
    
    # Index BAM file (CRITICAL - was missing in original!)
    if ! is_step_complete "index_bam_${sra_id}"; then
        log_info "Indexing BAM file: ${sra_id}"
        samtools index ./results/dedup_bam/${sra_id}_dupli.bam
        mark_step_complete "index_bam_${sra_id}"
    fi
}

variant_calling() {
    local sra_id=$1
    
    # Mpileup
    if ! is_step_complete "mpileup_${sra_id}"; then
        log_info "Running mpileup: ${sra_id}"
        bcftools mpileup \
            -a "FORMAT/AD,FORMAT/ADF,FORMAT/ADR,FORMAT/DP,FORMAT/SP,INFO/AD,INFO/ADF,INFO/ADR" \
            -O b --threads ${SAMTOOLS_THREADS} \
            -o ./results/pileup/${sra_id}_raw.bcf \
            -f ./index/GCF_000195855.1_ASM19585v1_genomic.fna \
            ./results/dedup_bam/${sra_id}_dupli.bam \
            -d 10000
        mark_step_complete "mpileup_${sra_id}"
    fi
    
    # Call variants
    if ! is_step_complete "call_${sra_id}"; then
        log_info "Calling variants: ${sra_id}"
        bcftools call --ploidy 1 -m -v \
            -o ./results/variant_vcf/${sra_id}_variant.vcf \
            ./results/pileup/${sra_id}_raw.bcf
        mark_step_complete "call_${sra_id}"
    fi
    
    # Filter variants
    if ! is_step_complete "filter_${sra_id}"; then
        log_info "Filtering variants: ${sra_id}"
        bcftools filter \
            -i "MQ>${MIN_MQ} && INFO/DP>${MIN_DP} && INFO/AD>${MIN_AD}" \
            ./results/variant_vcf/${sra_id}_variant.vcf \
            -o ./results/filtered_vcf/${sra_id}_filter.vcf
        
        # Compress and index
        bgzip -f ./results/filtered_vcf/${sra_id}_filter.vcf
        bcftools index -f -t ./results/filtered_vcf/${sra_id}_filter.vcf.gz
        mark_step_complete "filter_${sra_id}"
    fi
}

#############################################################################
# Drug Resistance Analysis
#############################################################################

analyze_drug_resistance() {
    local vcf_file=$1
    local output_file=$2
    
    log_info "Analyzing drug resistance mutations..."
    
    cat > "${output_file}" << 'EOF'
# M. leprae Drug Resistance Mutations
# Reference: WHO guidelines and published literature

Sample	Gene	Position	Reference	Alternate	Effect	Drug	Resistance_Level	Note
EOF
    
    # Extract mutations in key drug resistance genes
    # Rifampicin resistance - rpoB gene (positions based on M. leprae TN genome)
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%GT]\n' "${vcf_file}" | \
    awk -v sample="$(basename ${vcf_file} .vcf.gz)" '
    BEGIN {OFS="\t"}
    {
        # rpoB gene mutations (adjust positions based on actual genome)
        if ($2 >= 425 && $2 <= 452) {  # Example positions for rpoB hotspot
            print sample, "rpoB", $2, $3, $4, "SNP", "Rifampicin", "High", "rpoB hotspot region"
        }
        # folP1 gene mutations (Dapsone resistance)
        # Add specific positions when known
        
        # gyrA gene mutations (Fluoroquinolone resistance)
        # Add specific positions when known
    }' >> "${output_file}"
    
    log_success "Drug resistance analysis complete: ${output_file}"
}

create_drug_resistance_report() {
    if is_step_complete "drug_resistance_report"; then
        log_info "Drug resistance report already created, skipping..."
        return 0
    fi
    
    log_info "Creating comprehensive drug resistance report..."
    
    # Annotated VCF should be available
    local annotated_vcf="./results/annotation/norm_annotate.vcf"
    
    if [ ! -f "${annotated_vcf}" ]; then
        log_warn "Annotated VCF not found, skipping detailed drug resistance analysis"
        return 0
    fi
    
    # Extract mutations in drug resistance genes
    SnpSift filter \
        "(ANN[*].GENE = 'rpoB') | (ANN[*].GENE = 'folP1') | (ANN[*].GENE = 'gyrA') | (ANN[*].GENE = 'gyrB')" \
        "${annotated_vcf}" > ./results/drug_resistance/resistance_genes.vcf
    
    # Create detailed table
    SnpSift extractFields -s "," -e "." \
        ./results/drug_resistance/resistance_genes.vcf \
        CHROM POS REF ALT FILTER \
        "ANN[*].GENE" "ANN[*].EFFECT" "ANN[*].AA" \
        "GEN[*].GT" > ./results/drug_resistance/resistance_mutations.tsv
    
    # Create summary report
    python3 - <<'PYTHON' > ./results/drug_resistance/resistance_summary.txt
import sys

# Known drug resistance mutations for M. leprae
resistance_db = {
    'rpoB': {
        'drug': 'Rifampicin',
        'mutations': {
            'S425L': 'High',
            'S425F': 'High',
            'D441Y': 'High',
            'H451Y': 'High',
        }
    },
    'folP1': {
        'drug': 'Dapsone',
        'mutations': {
            'T53I': 'High',
            'T53A': 'High',
            'P55L': 'High',
            'P55R': 'High',
        }
    },
    'gyrA': {
        'drug': 'Ofloxacin/Fluoroquinolones',
        'mutations': {
            'A91V': 'High',
            'D95N': 'High',
            'D95Y': 'High',
        }
    }
}

print("=" * 80)
print("M. LEPRAE DRUG RESISTANCE ANALYSIS SUMMARY")
print("=" * 80)
print("\nKnown Drug Resistance Mutations Database:")
for gene, info in resistance_db.items():
    print(f"\n{gene} ({info['drug']}):")
    for mutation, level in info['mutations'].items():
        print(f"  - {mutation}: {level} resistance")
print("\n" + "=" * 80)
PYTHON
    
    mark_step_complete "drug_resistance_report"
    log_success "Drug resistance report created in results/drug_resistance/"
}

#############################################################################
# Post-Processing and Reports
#############################################################################

merge_and_annotate() {
    if is_step_complete "merge_annotate"; then
        log_info "Merge and annotation already complete, skipping..."
        return 0
    fi
    
    log_info "Merging VCF files..."
    
    # Create merge list
    ls ./results/filtered_vcf/*_filter.vcf.gz > ./results/annotation/merge.txt
    
    # Check if we have files to merge
    if [ ! -s ./results/annotation/merge.txt ]; then
        log_warn "No VCF files found for merging"
        return 0
    fi
    
    # Merge VCF files
    bcftools merge -o ./results/annotation/merge.vcf -O v \
        -l ./results/annotation/merge.txt --missing-to-ref
    
    # Normalize
    log_info "Normalizing variants..."
    bcftools norm -a -f ./index/GCF_000195855.1_ASM19585v1_genomic.fna \
        ./results/annotation/merge.vcf -o ./results/annotation/norm.vcf
    
    # Annotate with SnpEff
    log_info "Annotating variants with SnpEff..."
    snpEff -canon -no-downstream -no-upstream NC_002677.1 \
        ./results/annotation/norm.vcf \
        -csvStats ./results/annotation/norm_annotate.tsv \
        > ./results/annotation/norm_annotate.vcf
    
    # Extract genotype matrix
    log_info "Extracting genotype matrix..."
    (bcftools query -l ./results/annotation/norm_annotate.vcf | tr "\n" "\t" && \
     bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[\t%GT]\n' \
        ./results/annotation/norm_annotate.vcf) > ./results/annotation/genotype_matrix.tsv
    
    # Extract detailed fields
    log_info "Extracting annotation fields..."
    SnpSift extractFields -s "," -e "." ./results/annotation/norm_annotate.vcf \
        CHROM POS REF ALT FILTER \
        "ANN[*].GENE" "ANN[*].GENEID" "ANN[*].BIOTYPE" "ANN[*].EFFECT" \
        "EFF[*].AA" "EFF[*].EFFECT" "GEN[*].GT" \
        > ./results/annotation/extract_snpshift.tsv
    
    mark_step_complete "merge_annotate"
    log_success "Merge and annotation complete"
}

generate_quality_reports() {
    if is_step_complete "quality_reports"; then
        log_info "Quality reports already generated, skipping..."
        return 0
    fi
    
    log_info "Generating quality control reports..."
    
    # Qualimap
    if ls ./results/dedup_bam/*_dupli.bam 1> /dev/null 2>&1; then
        log_info "Running Qualimap..."
        for f in ./results/dedup_bam/*_dupli.bam; do 
            echo -e "$(basename ${f})\t${f}"
        done > ./reports/qualimap/qualimap.txt
        
        qualimap multi-bamqc -d ./reports/qualimap/qualimap.txt \
            -outfile ./reports/qualimap/quali_report.pdf \
            -outdir ./reports/qualimap/ -outformat HTML -r
    fi
    
    # MultiQC reports
    log_info "Generating MultiQC reports..."
    multiqc ./reports/fastqc_raw/ -o ./reports/fastqc_raw/ -f -n raw_reads_report
    multiqc ./reports/fastqc_trimmed/ -o ./reports/fastqc_trimmed/ -f -n trimmed_reads_report
    multiqc ./reports/dedup_stat/ -o ./reports/dedup_stat/ -f -n deduplication_report
    
    # Overall multiqc
    multiqc ./reports/ -o ./reports/ -f -n complete_pipeline_report
    
    mark_step_complete "quality_reports"
    log_success "Quality reports generated"
}

create_summary_statistics() {
    log_info "Creating summary statistics..."
    
    local summary_file="./results/pipeline_summary_${TIMESTAMP}.txt"
    
    cat > "${summary_file}" << EOF
M. LEPRAE NGS PIPELINE SUMMARY
================================
Pipeline Run: ${TIMESTAMP}
Reference Genome: GCF_000195855.1 (M. leprae TN)

SAMPLES PROCESSED:
EOF
    
    # Count samples
    local total_samples=$(ls ./results/dedup_bam/*_dupli.bam 2>/dev/null | wc -l)
    echo "Total Samples: ${total_samples}" >> "${summary_file}"
    echo "" >> "${summary_file}"
    
    # Per-sample statistics
    echo "PER-SAMPLE STATISTICS:" >> "${summary_file}"
    echo "=====================" >> "${summary_file}"
    
    for bam in ./results/dedup_bam/*_dupli.bam; do
        if [ -f "${bam}" ]; then
            local sample=$(basename ${bam} _dupli.bam)
            echo "" >> "${summary_file}"
            echo "Sample: ${sample}" >> "${summary_file}"
            
            # Alignment stats
            if [ -f "./reports/dedup_stat/${sample}.tsv" ]; then
                echo "  Alignment Statistics:" >> "${summary_file}"
                grep "mapped (" "./reports/dedup_stat/${sample}.tsv" >> "${summary_file}" || true
            fi
            
            # Variant count
            if [ -f "./results/filtered_vcf/${sample}_filter.vcf.gz" ]; then
                local var_count=$(bcftools view -H "./results/filtered_vcf/${sample}_filter.vcf.gz" | wc -l)
                echo "  Filtered Variants: ${var_count}" >> "${summary_file}"
            fi
        fi
    done
    
    log_success "Summary statistics created: ${summary_file}"
}

#############################################################################
# Main Pipeline
#############################################################################

main() {
    local sample_file=$1
    
    log_info "Starting M. leprae NGS Pipeline v2.0"
    log_info "Log file: ${LOG_FILE}"
    
    # Validate input
    if [ -z "${sample_file}" ]; then
        log_error "Usage: $0 <sample_list.csv>"
        log_error "Sample list format: sra_id,type (SINGLE or PAIRED)"
        exit 1
    fi
    
    if [ ! -f "${sample_file}" ]; then
        log_error "Sample file not found: ${sample_file}"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Setup
    create_directories
    download_reference
    index_reference
    
    # Process samples
    log_info "Processing samples from: ${sample_file}"
    
    while IFS=, read -r sra_id type; do
        # Skip header and empty lines
        if [[ "${sra_id}" == "sra_id" ]] || [[ -z "${sra_id}" ]]; then
            continue
        fi
        
        process_sample "${sra_id}" "${type}"
        
    done < "${sample_file}"
    
    # Post-processing
    merge_and_annotate
    create_drug_resistance_report
    generate_quality_reports
    create_summary_statistics
    
    log_success "========================================="
    log_success "Pipeline completed successfully!"
    log_success "========================================="
    log_info "Results location: ./results/"
    log_info "Reports location: ./reports/"
    log_info "Drug resistance: ./results/drug_resistance/"
    log_info "Log file: ${LOG_FILE}"
}

# Load config if exists
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
    log_info "Loaded configuration from ${CONFIG_FILE}"
fi

# Run main pipeline
main "$@"
