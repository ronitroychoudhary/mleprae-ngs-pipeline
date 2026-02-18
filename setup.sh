#!/bin/bash
#############################################################################
# Quick Setup and Test Script
# Helps you get started with the M. leprae NGS Pipeline
#############################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}M. leprae Pipeline Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Make scripts executable
echo -e "${GREEN}Step 1: Making scripts executable${NC}"
chmod +x vcf_pipeline_improved.sh
chmod +x pipeline_monitor.sh
chmod +x analyze_drug_resistance.py
echo "âœ“ Scripts are now executable"
echo ""

# Step 2: Check dependencies
echo -e "${GREEN}Step 2: Checking dependencies${NC}"
./pipeline_monitor.sh --dependencies
echo ""

read -p "Continue with setup? (yes/no): " continue_setup

if [ "$continue_setup" != "yes" ]; then
    echo "Setup cancelled. Install missing dependencies and run this script again."
    exit 0
fi

# Step 3: Create sample configuration
echo -e "${GREEN}Step 3: Creating sample configuration${NC}"

if [ ! -f "my_config.sh" ]; then
    cp pipeline_config.sh my_config.sh
    echo "âœ“ Created my_config.sh"
    echo ""
    echo "Edit my_config.sh to customize settings (optional):"
    echo "  - Thread counts"
    echo "  - Quality thresholds"
    echo "  - Email notifications"
else
    echo "âš  my_config.sh already exists, skipping"
fi
echo ""

# Step 4: Provide sample list template
echo -e "${GREEN}Step 4: Sample list preparation${NC}"

if [ ! -f "my_samples.csv" ]; then
    cat > my_samples.csv << 'EOF'
# Sample List for M. leprae NGS Pipeline
# Format: sra_id,type
# Replace with your actual SRA IDs
# Example entries below:

sra_id,type
SRR1234567,PAIRED
SRR1234568,SINGLE
EOF
    echo "âœ“ Created my_samples.csv template"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Edit my_samples.csv with your actual SRA accession numbers${NC}"
else
    echo "âš  my_samples.csv already exists"
fi
echo ""

# Step 5: Directory structure
echo -e "${GREEN}Step 5: Verifying directory structure${NC}"
./pipeline_monitor.sh --disk
echo ""

# Step 6: Testing option
echo -e "${GREEN}Step 6: Testing${NC}"
echo ""
echo "Would you like to run a test with sample data?"
echo "This will:"
echo "  1. Download reference genome"
echo "  2. Create indices"
echo "  3. Stop before processing samples (you can add real samples later)"
echo ""
read -p "Run reference genome setup test? (yes/no): " run_test

if [ "$run_test" = "yes" ]; then
    echo ""
    echo "Running reference genome setup..."
    echo "This may take 5-10 minutes..."
    echo ""
    
    # Create a dummy sample file for testing
    cat > test_reference_only.csv << 'EOF'
sra_id,type
EOF
    
    # Run pipeline - it will set up reference and stop (no samples to process)
    if ./vcf_pipeline_improved.sh test_reference_only.csv 2>&1 | tee test_setup.log; then
        echo ""
        echo -e "${GREEN}âœ“ Reference genome setup successful!${NC}"
        echo ""
        echo "Reference genome is ready at: ./index/"
        ls -lh ./index/GCF_000195855.1_ASM19585v1_genomic.fna* 2>/dev/null || echo "Checking files..."
    else
        echo ""
        echo -e "${YELLOW}âš  Setup test encountered issues${NC}"
        echo "Check test_setup.log for details"
    fi
    
    rm -f test_reference_only.csv
else
    echo "Skipping test. You can run it manually later."
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Edit my_samples.csv with your SRA accession numbers"
echo "   Format: sra_id,type (where type is SINGLE or PAIRED)"
echo ""
echo "2. (Optional) Edit my_config.sh to adjust settings"
echo ""
echo "3. Run the pipeline:"
echo "   source my_config.sh  # Load your settings"
echo "   ./vcf_pipeline_improved.sh my_samples.csv"
echo ""
echo "4. Monitor progress:"
echo "   ./pipeline_monitor.sh"
echo ""
echo "5. View results:"
echo "   results/annotation/           - Annotated variants"
echo "   results/drug_resistance/      - Drug resistance analysis"
echo "   reports/                      - Quality control reports"
echo ""
echo "For help:"
echo "  - See README.md for detailed documentation"
echo "  - See IMPROVEMENTS.md for list of all fixes"
echo "  - Run './pipeline_monitor.sh' for status checking"
echo ""
echo -e "${GREEN}Good luck with your analysis!${NC}"
