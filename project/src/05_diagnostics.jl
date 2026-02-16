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

function ols_t(y::Vector{Float64}, X::Matrix{Float64})
    β = X \ y
    e = y - X * β
    dof = size(X,1) - size(X,2)
    σ2 = sum(e.^2) / max(dof,1)
    vcov = σ2 * inv(X'X)
    se = sqrt.(diag(vcov))
    t = β ./ se
    return β, se, t
end

function placebo_lead_test(df::DataFrame, outcome::Symbol, shock::Symbol, leadk::Int)
    s_lead = lead(df[!, shock], leadk)
    y = df[!, outcome]
    x = [ones(length(y)) s_lead]
    keep = .!ismissing.(y) .& .!ismissing.(s_lead)
    y2 = Float64.(y[keep])
    x2 = Float64.(x[keep, :])
    if length(y2) < 20
        return missing, missing
    end
    β, se, t = ols_t(y2, x2)
    # rough normal approx p-value
    p = 2 * (1 - 0.5 * (1 + erf(abs(t[2]) / sqrt(2))))
    return β[2], p
end

function expected_sign_pass(irf::DataFrame, spec::String, outcome::String, shock::String, horizon::Int, expected::Int)
    sub = filter(r -> r.spec == spec && r.outcome == outcome && r.shock == shock && r.horizon == horizon, irf)
    if nrow(sub) == 0
        return missing, false
    end
    est = sub.beta[1]
    pass = expected > 0 ? est > 0 : est < 0
    return est, pass
end

function main()
    df = CSV.read(joinpath(PROC_DIR, "quarterly_analysis_ready.csv"), DataFrame)
    irf = CSV.read(joinpath(TABLE_DIR, "irf_estimates.csv"), DataFrame)

    out = DataFrame(model_id=String[], test_name=String[], estimate=Union{Missing,Float64}[], p_value=Union{Missing,Float64}[], expected_sign=String[], pass_flag=Bool[])

    # Placebo lead tests with preferred threshold p > 0.10.
    for (spec, shock) in [("baseline_frbsf", :mp_shock_frbsf), ("baseline_jk", :mp_shock_jk), ("baseline_jk", :oil_shock)]
        shock in names(df) || continue
        for leadk in (1,2)
            est, p = placebo_lead_test(df, :w_c, shock, leadk)
            pass = ismissing(p) ? false : p > 0.10
            push!(out, (spec, "placebo_w_c_$(shock)_lead$(leadk)", est, p, "0", pass))
        end
    end

    checks = [
        ("baseline_frbsf", "lGDPC1", "mp_shock_frbsf", 1, -1),
        ("baseline_frbsf", "UNRATE", "mp_shock_frbsf", 1, 1),
        ("baseline_frbsf", "lGDPC1", "oil_shock", 1, -1),
        ("baseline_frbsf", "UNRATE", "oil_shock", 1, 1),
    ]
    for (spec, outcome, shock, h, exp) in checks
        est, pass = expected_sign_pass(irf, spec, outcome, shock, h, exp)
        push!(out, (spec, "sign_$(outcome)_$(shock)_h$(h)", est, missing, exp > 0 ? "+" : "-", pass))
    end

    CSV.write(joinpath(TABLE_DIR, "diagnostics_summary.csv"), out)
    println("Saved diagnostics table: output/tables/diagnostics_summary.csv")
end

main()
