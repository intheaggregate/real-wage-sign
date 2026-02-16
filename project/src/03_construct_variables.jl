using CSV
using DataFrames
using Dates
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PROC_DIR = joinpath(ROOT, "data", "processed")

function add_logs!(df::DataFrame)
    for c in [:COMPNFB, :IPDNBS, :PCECTPI, :GDPC1, :HOANBS, :CPIAUCSL, :CPILFESL, :ECIWAG, :CES0500000003]
        if c in names(df)
            df[!, Symbol("l", c)] = log.(Float64.(df[!, c]))
        end
    end
    return df
end

function add_real_wages!(df::DataFrame)
    if all(in([:lCOMPNFB, :lIPDNBS]), Ref(names(df)))
        df.w_x = df.lCOMPNFB .- df.lIPDNBS
    end
    if all(in([:lCOMPNFB, :lPCECTPI]), Ref(names(df)))
        df.w_c = df.lCOMPNFB .- df.lPCECTPI
    end
    if all(in([:lECIWAG, :lPCECTPI]), Ref(names(df)))
        df.w_eci_c = df.lECIWAG .- df.lPCECTPI
    end
    if all(in([:lCES0500000003, :lPCECTPI]), Ref(names(df)))
        df.w_ahe_c = df.lCES0500000003 .- df.lPCECTPI
    end
    return df
end

lag(v, k) = [fill(missing, k); v[1:end-k]]

function sign_flip_if_needed!(df::DataFrame, shock::Symbol; gdp_col::Symbol=:lGDPC1)
    shock in names(df) || return false
    gdp_col in names(df) || return false

    tmp = DataFrame(s = df[!, shock], g = diff([missing; df[!, gdp_col]]))
    dropmissing!(tmp)
    if nrow(tmp) < 8
        return false
    end
    rho = cor(tmp.s, tmp.g)
    flipped = false
    # For contractionary/adverse supply shock, GDP growth response should be negative.
    if rho > 0
        df[!, shock] .*= -1
        flipped = true
    end
    return flipped
end

function main()
    inpath = joinpath(PROC_DIR, "quarterly_balanced.csv")
    df = CSV.read(inpath, DataFrame)
    sort!(df, :q)
    add_logs!(df)
    add_real_wages!(df)

    flipped_mp_frb = sign_flip_if_needed!(df, :mp_shock_frbsf)
    flipped_mp_jk = sign_flip_if_needed!(df, :mp_shock_jk)
    flipped_oil = sign_flip_if_needed!(df, :oil_shock)

    # Predetermined state and controls
    if :UNRATE in names(df)
        df.UNRATE_l1 = lag(df.UNRATE, 1)
    end
    if :HOANBS in names(df)
        df.lHOANBS_l1 = lag(df.lHOANBS, 1)
    end

    CSV.write(joinpath(PROC_DIR, "quarterly_analysis_ready.csv"), df)

    flips = DataFrame(
        shock=["mp_shock_frbsf","mp_shock_jk","oil_shock"],
        flipped=[flipped_mp_frb, flipped_mp_jk, flipped_oil],
    )
    CSV.write(joinpath(PROC_DIR, "shock_sign_flips.csv"), flips)
    println("Constructed analysis dataset and shock sign-flip summary.")
end

main()
