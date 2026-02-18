# M. leprae NGS Analysis Pipeline v2.0

Complete pipeline for analyzing *Mycobacterium leprae* genomic data with automated drug resistance detection.

## ðŸŽ¯ Key Features

### New in Version 2.0

1. **Robust Error Handling**
   - Automatic error detection and logging
   - Resume capability from last successful step
   - Comprehensive error reporting

2. **Drug Resistance Analysis**
   - Detection of known resistance mutations in:
     - rpoB (Rifampicin resistance)
     - folP1 (Dapsone resistance)
     - gyrA/gyrB (Fluoroquinolone resistance)
   - Automated resistance reporting
   - Interpretation guidelines

3. **Process Automation**
   - Configurable settings via config file
   - Automatic quality control reporting
   - Summary statistics generation
   - Resume interrupted runs

4. **Bug Fixes from v1.0**
   - âœ… Fixed missing BAM indexing (critical!)
   - âœ… Fixed reference genome path issues
   - âœ… Added proper file validation
   - âœ… Improved resource management
   - âœ… Fixed normalization step reference path

## ðŸ“‹ Requirements

### Software Dependencies

```bash
# SRA toolkit
prefetch, fasterq-dump

# Quality control
fastqc, fastp, multiqc, qualimap

# Alignment
bwa, samtools (>= 1.10)

# Variant calling
bcftools, picard

# Annotation
snpEff, SnpSift

# Utilities
curl, unzip, pigz, bgzip, tabix, python3
```

### Installation Example (Ubuntu/Debian)

```bash
# Install via conda (recommended)
conda create -n mleprae_pipeline -c bioconda -c conda-forge \
    sra-tools fastqc fastp bwa samtools bcftools picard \
    snpeff snpsift qualimap multiqc pigz

conda activate mleprae_pipeline

# Or install individually
sudo apt-get update
sudo apt-get install -y bwa samtools bcftools fastqc \
    curl unzip pigz tabix python3
```

## ðŸš€ Quick Start

### 1. Prepare Sample List

Create a CSV file with your samples (see `sample_list_template.csv`):

```csv
sra_id,type
SRR1234567,PAIRED
SRR1234568,SINGLE
SRR1234569,PAIRED
```

### 2. Configure Pipeline (Optional)

```bash
# Copy and edit configuration file
cp pipeline_config.sh my_config.sh
nano my_config.sh

# Adjust parameters:
# - THREADS (default: 8)
# - Quality thresholds
# - Email notifications
```

### 3. Run Pipeline

```bash
# Make scripts executable
chmod +x vcf_pipeline_improved.sh
chmod +x analyze_drug_resistance.py

# Run pipeline
./vcf_pipeline_improved.sh samples.csv

# Or with custom config
source my_config.sh
./vcf_pipeline_improved.sh samples.csv
```

## ðŸ“ Directory Structure

After running, your directory will contain:

```
.
â”œâ”€â”€ fastq/
â”‚   â”œâ”€â”€ rawdata/          # Downloaded raw FASTQ files
â”‚   â””â”€â”€ trimmed/          # Quality-trimmed reads
â”œâ”€â”€ index/                # Reference genome and indices
â”œâ”€â”€ results/
â”‚   â”œâ”€â”€ aligned_bam/      # Aligned reads
â”‚   â”œâ”€â”€ sorted_bam/       # Sorted alignments
â”‚   â”œâ”€â”€ dedup_bam/        # Deduplicated BAMs
â”‚   â”œâ”€â”€ pileup/           # BCF pileups
â”‚   â”œâ”€â”€ variant_vcf/      # Raw variant calls
â”‚   â”œâ”€â”€ filtered_vcf/     # Filtered variants
â”‚   â”œâ”€â”€ annotation/       # Annotated variants
â”‚   â””â”€â”€ drug_resistance/  # Resistance analysis results
â”œâ”€â”€ reports/
â”‚   â”œâ”€â”€ fastqc_raw/       # Raw data QC
â”‚   â”œâ”€â”€ fastqc_trimmed/   # Trimmed data QC
â”‚   â”œâ”€â”€ qualimap/         # Alignment QC
â”‚   â””â”€â”€ *.html            # MultiQC reports
â””â”€â”€ logs/                 # Pipeline logs
```

## ðŸ”¬ Drug Resistance Analysis

### Automatic Detection

The pipeline automatically screens for mutations in key genes:

#### Rifampicin Resistance (rpoB)
- S425L, S425F (most common)
- D441Y, D441V
- H451Y, H451D
- S456L

#### Dapsone Resistance (folP1)
- T53I, T53A
- P55L, P55R, P55S

#### Fluoroquinolone Resistance (gyrA/gyrB)
- A91V, A91T
- D95N, D95Y, D95G

### Resistance Report Locations

After running the pipeline:
- `results/drug_resistance/resistance_mutations.tsv` - Detailed mutation table
- `results/drug_resistance/resistance_summary.txt` - Human-readable report
- `results/drug_resistance/resistance_genes.vcf` - VCF with resistance variants only

### Manual Analysis

For custom analysis:

```bash
python3 analyze_drug_resistance.py \
    results/annotation/norm_annotate.vcf \
    -o custom_resistance.tsv \
    -r custom_report.txt
```

## ðŸ”„ Resume Capability

If the pipeline is interrupted:

```bash
# Simply re-run - it will resume from the last successful step
./vcf_pipeline_improved.sh samples.csv

# To start fresh (ignore previous progress)
rm .pipeline_resume
./vcf_pipeline_improved.sh samples.csv
```

## ðŸ“Š Quality Control

The pipeline generates comprehensive QC reports:

1. **Raw Data QC** (`reports/fastqc_raw/`)
   - Per-base quality scores
   - Sequence length distribution
   - Adapter content

2. **Trimmed Data QC** (`reports/fastqc_trimmed/`)
   - Post-trimming quality metrics
   - Fastp HTML reports

3. **Alignment QC** (`reports/qualimap/`)
   - Coverage statistics
   - Mapping quality
   - Insert size distribution

4. **Overall Report** (`reports/complete_pipeline_report.html`)
   - Multi QC comprehensive report

## âš™ï¸ Configuration Options

### Thread Settings

```bash
export THREADS=8                # General processing threads
export SAMTOOLS_THREADS=4       # Samtools operations
```

### Quality Thresholds

```bash
export MIN_QUALITY=20           # Minimum base quality
export MIN_LENGTH=50            # Minimum read length
export MIN_MQ=30                # Minimum mapping quality
export MIN_DP=5                 # Minimum read depth
export MIN_AD=3                 # Minimum alternate allele depth
```

## ðŸ“ Logging

All pipeline activities are logged:

- `logs/pipeline_YYYYMMDD_HHMMSS.log` - Complete pipeline log
- `logs/error_YYYYMMDD_HHMMSS.log` - Error-specific log

Check logs for troubleshooting:

```bash
# View latest log
tail -f logs/pipeline_*.log

# Search for errors
grep ERROR logs/pipeline_*.log
```

## ðŸ› Common Issues and Solutions

### Issue: "Command not found"
**Solution**: Ensure all dependencies are installed and in PATH

```bash
# Check if command exists
command -v bwa
command -v samtools

# If using conda, ensure environment is activated
conda activate mleprae_pipeline
```

### Issue: "Reference genome download fails"
**Solution**: Download manually or check internet connection

```bash
# Manual download
curl -L "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/195/855/GCF_000195855.1_ASM19585v1/GCF_000195855.1_ASM19585v1_genomic.fna.gz" \
    -o index/reference.fna.gz
gunzip index/reference.fna.gz
mv index/reference.fna index/GCF_000195855.1_ASM19585v1_genomic.fna
```

### Issue: "Out of memory"
**Solution**: Reduce thread count or increase available RAM

```bash
# Reduce threads
export THREADS=2
export SAMTOOLS_THREADS=1
```

### Issue: "Pipeline stops unexpectedly"
**Solution**: Check error log and resume

```bash
# Check error log
cat logs/error_*.log

# Resume from last successful step
./vcf_pipeline_improved.sh samples.csv
```

## ðŸ”¬ Interpretation of Results

### Variant Filtering

Variants are filtered based on:
- Mapping Quality (MQ) > 30
- Total Depth (DP) > 5
- Alternate Allele Depth (AD) > 3

### Drug Resistance Classification

- **HIGH**: Strong evidence, treatment likely to fail
- **MODERATE**: Possible resistance, use with caution
- **LOW**: Limited evidence, clinical significance uncertain

### Clinical Recommendations

If resistance mutations are detected:
1. Consult WHO guidelines for M. leprae treatment
2. Consider alternative drug regimens
3. Perform phenotypic drug susceptibility testing if possible
4. Monitor treatment response closely

## ðŸ“š References

1. WHO Guidelines for the Diagnosis, Treatment and Prevention of Leprosy (2018)
2. Benjak et al. (2018) - Phylogenomics and antimicrobial resistance of M. leprae
3. Cambau & Drancourt (2014) - Drug resistance in leprosy
4. Matsuoka et al. (2007) - Drug resistance in leprosy

## ðŸ†˜ Support

For issues or questions:
1. Check the logs in `logs/` directory
2. Review common issues section above
3. Open an issue on GitHub (if applicable)
4. Contact your bioinformatics support team

## ðŸ“„ License

This pipeline is provided as-is for research purposes. Consult with appropriate regulatory bodies for clinical use.

## ðŸ™ Acknowledgments

- NCBI for reference genomes
- SnpEff/SnpSift developers
- Bioconda community
- WHO Leprosy Programme

---

**Version**: 2.0  
**Last Updated**: 2024  
**Contact**: CSIR-IHBT, Studio of Computational biology and bioinformatics
