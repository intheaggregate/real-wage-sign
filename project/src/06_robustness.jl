using CSV
using DataFrames
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PROC_DIR = joinpath(ROOT, "data", "processed")
const TABLE_DIR = joinpath(ROOT, "output", "tables")
mkpath(TABLE_DIR)

lag(v, k) = [fill(missing, k); v[1:end-k]]

function vintage_robustness(df::DataFrame)
    # Placeholder scaffold: compare latest oil vintage to previous if available in raw dir.
    # This script stores a reproducible hook rather than downloading historical vintages silently.
    has_oil = :oil_shock in names(df)
    return DataFrame(check=["oil_vintage_compare_available"], value=[has_oil])
end

function deflator_robustness(df::DataFrame)
    out = DataFrame(metric=String[], corr=Float64[])
    if all(in([:w_c,:w_x]), Ref(names(df)))
        tmp = dropmissing(df[:, [:w_c, :w_x]])
        if nrow(tmp) > 2
            push!(out, ("corr_w_c_w_x", cor(tmp.w_c, tmp.w_x)))
        end
    end
    if all(in([:w_eci_c,:w_c]), Ref(names(df)))
        tmp = dropmissing(df[:, [:w_eci_c, :w_c]])
        if nrow(tmp) > 2
            push!(out, ("corr_w_eci_c_w_c", cor(tmp.w_eci_c, tmp.w_c)))
        end
    end
    if all(in([:w_ahe_c,:w_c]), Ref(names(df)))
        tmp = dropmissing(df[:, [:w_ahe_c, :w_c]])
        if nrow(tmp) > 2
            push!(out, ("corr_w_ahe_c_w_c", cor(tmp.w_ahe_c, tmp.w_c)))
        end
    end
    return out
end

function state_dependence_inputs(df::DataFrame)
    out = DataFrame(q=df.q)
    if :UNRATE in names(df)
        out.slack_l1 = lag(df.UNRATE, 1)
    end
    if :mp_shock_frbsf in names(df) && :UNRATE in names(df)
        out.mp_x_slack = lag(df.UNRATE, 1) .* df.mp_shock_frbsf
    end
    return out
end

function main()
    df = CSV.read(joinpath(PROC_DIR, "quarterly_analysis_ready.csv"), DataFrame)
    CSV.write(joinpath(TABLE_DIR, "robustness_vintage_hook.csv"), vintage_robustness(df))
    CSV.write(joinpath(TABLE_DIR, "robustness_deflator_correlations.csv"), deflator_robustness(df))
    CSV.write(joinpath(PROC_DIR, "state_dependence_inputs.csv"), state_dependence_inputs(df))
    println("Saved robustness artifacts.")
end

main()
