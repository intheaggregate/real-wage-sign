using CSV
using DataFrames
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const TABLE_DIR = joinpath(ROOT, "output", "tables")
const FIG_DIR = joinpath(ROOT, "output", "figs")
mkpath(FIG_DIR)

function sign(x)
    x > 0 ? "+" : x < 0 ? "-" : "0"
end

function build_sign_table(irf::DataFrame)
    horizons = Set([0, 1, 4])
    sub = filter(r -> r.horizon in horizons, irf)
    g = combine(groupby(sub, [:spec, :outcome, :shock, :horizon]), :beta => first => :beta)
    g.sign = sign.(g.beta)
    return g
end

function maybe_plot(irf::DataFrame)
    try
        @eval using Plots
    catch err
        @warn "Plots.jl unavailable; skipping figures." err
        return
    end

    for spec in unique(irf.spec)
        for outcome in unique(irf.outcome)
            sub = filter(r -> r.spec == spec && r.outcome == outcome, irf)
            nrow(sub) == 0 && continue
            p = plot(title="IRF: $(outcome) ($(spec))", xlabel="h", ylabel="response")
            for sh in unique(sub.shock)
                ss = filter(:shock => ==(sh), sub)
                sort!(ss, :horizon)
                plot!(p, ss.horizon, ss.beta, label=sh)
                plot!(p, ss.horizon, ss.lo90, label="$(sh) lo90", ls=:dash, alpha=0.35)
                plot!(p, ss.horizon, ss.hi90, label="$(sh) hi90", ls=:dash, alpha=0.35)
            end
            savefig(p, joinpath(FIG_DIR, "irf_$(spec)_$(outcome).png"))
        end
    end
end

function main()
    irf = CSV.read(joinpath(TABLE_DIR, "irf_estimates.csv"), DataFrame)
    sign_tbl = build_sign_table(irf)
    CSV.write(joinpath(TABLE_DIR, "irf_sign_summary_h014.csv"), sign_tbl)
    maybe_plot(irf)
    println("Saved sign summary and (if available) IRF figures.")
end

main()
