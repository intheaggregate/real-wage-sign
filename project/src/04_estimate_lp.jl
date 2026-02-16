using CSV
using DataFrames
using Statistics
using LinearAlgebra

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PROC_DIR = joinpath(ROOT, "data", "processed")
const TABLE_DIR = joinpath(ROOT, "output", "tables")
mkpath(TABLE_DIR)

lag(v, k) = [fill(missing, k); v[1:end-k]]
lead(v, h) = [v[h+1:end]; fill(missing, h)]

function build_lag_controls!(df::DataFrame, cols::Vector{Symbol}, p::Int)
    for c in cols
        c in names(df) || continue
        for j in 1:p
            newc = Symbol("$(c)_l$(j)")
            df[!, newc] = lag(df[!, c], j)
        end
    end
end

function ols(y::Vector{Float64}, X::Matrix{Float64})
    β = X \ y
    e = y - X * β
    dof = size(X, 1) - size(X, 2)
    σ2 = sum(e .^ 2) / max(dof, 1)
    vcov = σ2 * inv(X'X)
    se = sqrt.(diag(vcov))
    return β, se
end

function lp_manual(df::DataFrame, y::Symbol, shocks::Vector{Symbol}; p::Int=4, H::Int=12)
    controls_base = [:w_c, :w_x, :lGDPC1, :UNRATE]
    build_lag_controls!(df, controls_base, p)

    # Explicitly lagged controls to avoid contemporaneous bad controls.
    lag_controls = Symbol[]
    for c in controls_base, j in 1:p
        cc = Symbol("$(c)_l$(j)")
        cc in names(df) && push!(lag_controls, cc)
    end

    rows = DataFrame(outcome=String[], shock=String[], horizon=Int[], beta=Float64[], se=Float64[], lo90=Float64[], hi90=Float64[], lo68=Float64[], hi68=Float64[])

    for h in 0:H
        yh = lead(df[!, y], h)
        work = DataFrame(yh=yh)
        for s in shocks
            work[!, s] = df[!, s]
        end
        for c in lag_controls
            work[!, c] = df[!, c]
        end
        dropmissing!(work)
        if nrow(work) < (length(shocks) + length(lag_controls) + 8)
            continue
        end

        X = ones(nrow(work), 1 + length(shocks) + length(lag_controls))
        for (i, s) in enumerate(shocks)
            X[:, 1 + i] = Float64.(work[!, s])
        end
        for (j, c) in enumerate(lag_controls)
            X[:, 1 + length(shocks) + j] = Float64.(work[!, c])
        end
        yvec = Float64.(work.yh)
        β, se = ols(yvec, X)

        for (i, s) in enumerate(shocks)
            b = β[1 + i]
            sde = se[1 + i]
            push!(rows, (
                outcome=String(y), shock=String(s), horizon=h, beta=b, se=sde,
                lo90=b - 1.645*sde, hi90=b + 1.645*sde,
                lo68=b - 1.0*sde, hi68=b + 1.0*sde,
            ))
        end
    end

    return rows
end

function run_all_specs(df::DataFrame)
    outcomes = [:w_c, :w_x, :lGDPC1, :UNRATE, :lHOANBS]
    specs = Dict(
        "baseline_frbsf" => [:mp_shock_frbsf, :oil_shock],
        "baseline_jk" => [:mp_shock_jk, :oil_shock],
        "jk_with_info" => [:mp_shock_jk, :cbi_shock_jk, :oil_shock],
    )

    full = DataFrame()
    for (spec, shocks) in specs
        valid_shocks = [s for s in shocks if s in names(df)]
        for y in outcomes
            y in names(df) || continue
            r = lp_manual(copy(df), y, valid_shocks)
            if nrow(r) > 0
                r.spec .= spec
                full = nrow(full) == 0 ? r : vcat(full, r)
            end
        end
    end
    return full
end

function main()
    df = CSV.read(joinpath(PROC_DIR, "quarterly_analysis_ready.csv"), DataFrame)
    # Runtime guard on no contemporaneous extensive-margin controls.
    @info "LP guard: only lagged controls are included; no contemporaneous UNRATE/HOANBS/employment controls in wage equations."

    irf = run_all_specs(df)
    CSV.write(joinpath(TABLE_DIR, "irf_estimates.csv"), irf)
    println("Saved output/tables/irf_estimates.csv")
end

main()
