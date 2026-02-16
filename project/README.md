# Real Wage Sign LP Pipeline (Julia)

This project implements a quarterly local-projections pipeline for real wages, activity, and extensive-margin outcomes using external oil and monetary shocks.

## What this does

- Downloads and records provenance for:
  - Känzig oil supply news shocks (latest vintage auto-detected via GitHub API).
  - FRBSF monetary policy surprise data (orthogonalized-series source file).
  - Jarociński–Karadi monthly MP and information shocks.
  - FRED macro series (if `FRED_API_KEY` is set).
- Builds a quarterly dataset (1994Q1+ baseline overlap).
- Constructs product and consumption real wages:
  - `w_x = log(COMPNFB) - log(IPDNBS)`
  - `w_c = log(COMPNFB) - log(PCECTPI)`
- Estimates LP-style IRFs with explicit lagged controls (no contemporaneous extensive-margin controls in wage equations).
- Runs diagnostics:
  - lead-placebo checks,
  - sign-validity checks.
- Produces robustness artifacts and sign-summary tables.
- Saves IRF plots if `Plots.jl` is available.

## Repository layout

```
project/
  Project.toml
  Manifest.toml
  data/
    raw/
    processed/
  src/
    01_download_data.jl
    02_build_dataset_quarterly.jl
    03_construct_variables.jl
    04_estimate_lp.jl
    05_diagnostics.jl
    06_robustness.jl
    07_plots_tables.jl
  output/
    figs/
    tables/
```

## Run instructions

From `project/`:

```bash
# 1) Install dependencies (requires Julia installed)
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# 2) Optional: FRED key for automatic macro downloads
export FRED_API_KEY="<your_fred_api_key>"

# 3) Execute pipeline in order
julia --project=. src/01_download_data.jl
julia --project=. src/02_build_dataset_quarterly.jl
julia --project=. src/03_construct_variables.jl
julia --project=. src/04_estimate_lp.jl
julia --project=. src/05_diagnostics.jl
julia --project=. src/06_robustness.jl
julia --project=. src/07_plots_tables.jl
```

## Robust defaults and fallback behavior

- If FRBSF or GitHub downloads fail, scripts emit clear warnings and continue, writing download status in `output/tables/download_status.csv`.
- If FRED credentials are missing, FRED downloads are skipped with warning.
- Provenance is recorded in `data/raw/provenance_manifest.csv` with SHA256 hashes.
- Aggregation rules are source-specific and documented in `data/processed/series_metadata.csv`:
  - monthly shocks → quarterly sum,
  - unemployment (monthly) → quarterly average.

## Reproducibility

- `Manifest.toml` is a bootstrap placeholder in this environment because Julia was unavailable during generation.
- After installing Julia, generate a fully pinned manifest:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.resolve()'
```

- Downstream scripts read local files from `data/raw` and do not force redownloads.

## Key outputs

- `data/processed/quarterly_analysis_ready.csv`
- `output/tables/irf_estimates.csv`
- `output/tables/diagnostics_summary.csv`
- `output/tables/irf_sign_summary_h014.csv`
- `output/figs/*.png` (when plotting backend available)
