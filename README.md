# migrate-to-db-nf

Nextflow pipeline for importing GWAS mapping TSV files to a Parquet database.

## Overview

This pipeline migrates raw mapping files from the NemaScan simulation pipeline into a normalized Parquet database structure optimized for downstream analysis. It provides process-level parallelism suitable for SLURM-managed HPC clusters.

Optionally, the pipeline can also run QTL analysis to flag significant markers and define QTL intervals using both Bonferroni (BF) and EIGEN-based significance thresholds.

## Quick Start

### Local execution

```bash
nextflow run main.nf --input /path/to/mapping_files --output ./results/db
```

### With QTL analysis

```bash
nextflow run main.nf \
    --input /path/to/mapping_files \
    --output ./results/db \
    --analyze_qtl
```

### SLURM HPC

```bash
nextflow run main.nf \
    --input /path/to/mapping_files \
    --output  \
    -profile rockfish
```

## Parameters

### Migration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--input` | Directory containing mapping TSV files (required) | - |
| `--eigen_dir` | Directory containing EIGEN files (optional) | auto-detect |
| `--output` | Output database directory | `./results/db` |
| `--overwrite` | Replace existing mappings | `false` |
| `--batch_name` | Name for this batch (for reports) | input dir name |

### QTL Analysis Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--analyze_qtl` | Enable QTL analysis after migration | `false` |
| `--alpha` | Significance level for thresholds | `0.05` |
| `--ci_size` | Markers left/right of peak for confidence interval | `150` |
| `--snp_grouping` | Max marker distance to group into same QTL | `1000` |
| `--qtl_output` | QTL output directory | `{output}/qtl` |

### Standalone QTL Re-run Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--mapping_db` | Path to existing mapping database (required for standalone) | - |
| `--population` | Filter to specific population | all |
| `--algorithm` | Filter to INBRED or LOCO | all |

## Pipeline Architecture

```
Phase 1: Discovery
DISCOVER_FILES -> BUILD_EIGEN_LOOKUP -> IDENTIFY_MARKER_SETS
       |                  |                    |
       v                  v                    v
  mapping_files      eigen_lookup         marker_sets

Phase 2: Pre-create marker sets
       |                  +--------------------+
       |                  |
       v                  v
  WRITE_MARKER_SETS (parallel per marker set)

Phase 3: Process mappings
       |
       v
  PROCESS_MAPPINGS (parallel per file)

Phase 4: Aggregate results
       |
       v
  AGGREGATE_METADATA

Phase 5: QTL Analysis (optional, --analyze_qtl)
       |
       v
  DISCOVER_QTL_BATCHES -> ANALYZE_QTL_BATCH -> AGGREGATE_QTL_RESULTS
                        (parallel per pop/algo)
```

### Phases

1. **Discovery Phase** (local, fast)
   - Scan input directory for `*_mapping.tsv` files
   - Build EIGEN lookup table from `Genotype_Matrix/` directory
   - Identify unique population+MAF combinations

2. **Marker Set Creation** (parallel per marker set)
   - Create marker sets before processing mappings
   - Include EIGEN values for threshold calculations

3. **Processing Phase** (SLURM, parallel per-file)
   - Each mapping file processed independently
   - Outputs individual partition Parquet + status JSON

4. **Aggregation Phase** (single job)
   - Combine status files
   - Write consolidated metadata table

5. **QTL Analysis Phase** (optional, parallel per population/algorithm)
   - Discover unique (population, algorithm) batches
   - For each batch: compute BF and EIGEN thresholds, define QTL intervals
   - Aggregate results into summary files

## Profiles

| Profile | Description |
|---------|-------------|
| `standard` | Local execution (no container) |
| `docker` | Local execution with Docker container |
| `rockfish` | JHU Rockfish cluster (SLURM + Singularity) |
| `test` | Use test data |

### Example: Local with Docker

```bash
nextflow run main.nf \
    --input /path/to/data \
    --output ./results/db \
    -profile docker
```

### Example: Rockfish

```bash
nextflow run main.nf \
    --input /path/to/data \
    --output ./results/db \
    -profile rockfish
```

## Output Structure

```
results/db/
├── markers/
│   └── {population}_{maf}_markers.parquet
├── mappings/
│   └── population={pop}/
│       └── mapping_id={id}/
│           └── data.parquet
├── mappings_metadata.parquet
├── marker_set_metadata.parquet
├── qtl/                                    # (when --analyze_qtl enabled)
│   ├── qtl_regions/
│   │   └── {population}_{algorithm}_qtl_regions.parquet
│   ├── analysis_summary.parquet
│   ├── analysis_metadata.parquet
│   └── qtl_analysis_summary.txt
└── pipeline_info/
    ├── execution_timeline_*.html
    ├── execution_report_*.html
    └── execution_trace_*.txt
```

### QTL Database Schema

**qtl_regions** (one row per QTL interval):
- `mapping_id`, `threshold_method` (BF/EIGEN), `peak_id`
- `CHROM`, `startPOS`, `peakPOS`, `endPOS`, `interval_size`
- `n_sig_markers`, `max_log10p`, `peak_marker`, `sig_threshold_value`
- `ci_size`, `snp_grouping`, `algorithm`, `population`, `maf`

**analysis_summary** (one row per mapping × threshold):
- `mapping_id`, `threshold_method`, `population`, `maf`, `algorithm`
- `n_markers`, `n_significant`, `pct_significant`, `n_qtl`, `max_log10p`
- `threshold_value`, `ci_size`, `snp_grouping`

## Standalone QTL Re-runs

After migration, you can re-run QTL analysis with different parameters using the standalone workflow:

```bash
# Re-run with different CI size and SNP grouping
nextflow run workflows/analyze_qtl.nf \
    --mapping_db results/db \
    --ci_size 200 \
    --snp_grouping 500

# Filter to specific population
nextflow run workflows/analyze_qtl.nf \
    --mapping_db results/db \
    --population ct.fullpop.20210901

# Filter to specific algorithm
nextflow run workflows/analyze_qtl.nf \
    --mapping_db results/db \
    --algorithm INBRED

# Custom output directory
nextflow run workflows/analyze_qtl.nf \
    --mapping_db results/db \
    --qtl_output results/qtl_rerun
```

Re-running QTL analysis will **overwrite** existing QTL results for the same parameters.

## Container

Build the Docker container:

```bash
cd docker
docker build -t migrate-to-db:latest .
docker push yourusername/migrate-to-db:latest
```

On HPC, Singularity will auto-convert:

```bash
singularity pull docker://yourusername/migrate-to-db:latest
```

## Development

### Running tests

```bash
nextflow run main.nf -profile test
```