using CSV
using DataFrames
using Dates
using Statistics
using XLSX

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RAW_DIR = joinpath(ROOT, "data", "raw")
const PROC_DIR = joinpath(ROOT, "data", "processed")
mkpath(PROC_DIR)

quarter_date(d::Date) = Date(year(d), month(d) in 1:3 ? 3 : month(d) in 4:6 ? 6 : month(d) in 7:9 ? 9 : 12, 1)

function coalesce_col(df::DataFrame, candidates::Vector{String})
    names_l = Dict(lowercase(string(n)) => n for n in names(df))
    for c in candidates
        k = lowercase(c)
        haskey(names_l, k) && return names_l[k]
    end
    return nothing
end

function parse_date_col(v)
    if v isa Date
        return v
    elseif v isa DateTime
        return Date(v)
    else
        s = strip(string(v))
        for fmt in (dateformat"yyyy-mm-dd", dateformat"m/d/y", dateformat"yyyy-m-d", dateformat"y-m-d")
            try
                return Date(s, fmt)
            catch
            end
        end
        try
            return Date(s)
        catch
            return missing
        end
    end
end

function read_fred_series(series_id::String)
    f = joinpath(RAW_DIR, "fred_$(series_id).csv")
    isfile(f) || return DataFrame(q=Date[], Symbol(series_id)=>Float64[])
    df = CSV.read(f, DataFrame)
    dcol = coalesce_col(df, ["date"])
    vcol = coalesce_col(df, ["value", series_id])
    dcol === nothing && error("No date column in $f")
    vcol === nothing && error("No value column in $f")

    out = DataFrame(date = map(parse_date_col, df[!, dcol]), value = df[!, vcol])
    dropmissing!(out)
    out.value = parse.(Float64, string.(out.value))
    out.q = quarter_date.(out.date)

    agg = combine(groupby(out, :q), :value => mean => Symbol(series_id))
    return agg
end

function read_kanzig_monthly()
    path = joinpath(RAW_DIR, "oilSupplyNewsShocks_latest.xlsx")
    isfile(path) || return DataFrame(q=Date[], oil_shock=Float64[])
    xf = XLSX.readxlsx(path)

    # Use first sheet and infer columns.
    sheet = xf[1]
    df = DataFrame(sheet)
    dcol = coalesce_col(df, ["date","month","obs_date"])
    scol = coalesce_col(df, ["oil_supply_news_shock","oilshocksupplynews","oil_supply_news","shock","oilsupplynewsshock"])
    if dcol === nothing || scol === nothing
        # fallback: first column date, second numeric
        dcol = names(df)[1]
        scol = names(df)[2]
    end

    out = DataFrame(date = map(parse_date_col, df[!, dcol]), shock = df[!, scol])
    dropmissing!(out)
    out.shock = parse.(Float64, string.(out.shock))
    out.q = quarter_date.(out.date)
    qdf = combine(groupby(out, :q), :shock => sum => :oil_shock)

    # validation row
    if nrow(qdf) > 0
        sample_q = qdf.q[end]
        sample_m = filter(:q => ==(sample_q), out)
        println("Känzig aggregation check for $(sample_q): monthly=$(sample_m.shock), qsum=$(qdf[qdf.q .== sample_q, :oil_shock][1])")
    end
    return qdf
end

function read_frbsf_monthly()
    path = joinpath(RAW_DIR, "monetary-policy-surprises-data.xlsx")
    isfile(path) || return DataFrame(q=Date[], mp_shock_frbsf=Float64[])
    xf = XLSX.readxlsx(path)
    sheet = xf[1]
    df = DataFrame(sheet)

    dcol = coalesce_col(df, ["date","fomc_date","meeting_date"])
    cands = ["orthogonalized", "orth", "ff4_tc", "ff4", "target"]
    scol = nothing
    for n in names(df)
        nn = lowercase(string(n))
        if any(occursin(c, nn) for c in cands)
            scol = n
            break
        end
    end
    if dcol === nothing || scol === nothing
        dcol = names(df)[1]
        scol = names(df)[2]
    end

    out = DataFrame(date = map(parse_date_col, df[!, dcol]), shock = df[!, scol])
    dropmissing!(out)
    out.shock = parse.(Float64, string.(out.shock))
    out.q = quarter_date.(out.date)
    qdf = combine(groupby(out, :q), :shock => sum => :mp_shock_frbsf)

    if nrow(qdf) > 0
        sample_q = qdf.q[end]
        sample_m = filter(:q => ==(sample_q), out)
        println("FRBSF aggregation check for $(sample_q): monthly=$(sample_m.shock), qsum=$(qdf[qdf.q .== sample_q, :mp_shock_frbsf][1])")
    end
    return qdf
end

function read_jk_monthly()
    path = joinpath(RAW_DIR, "shocks_fed_jk_m.csv")
    isfile(path) || return DataFrame(q=Date[], mp_shock_jk=Float64[], cbi_shock_jk=Float64[])
    df = CSV.read(path, DataFrame)

    dcol = coalesce_col(df, ["date","month"])
    mpcol = coalesce_col(df, ["mp", "mp_median", "monetary_policy_shock"])
    cbicol = coalesce_col(df, ["cbi", "cbi_median", "central_bank_information_shock"])
    if dcol === nothing
        dcol = names(df)[1]
    end
    if mpcol === nothing || cbicol === nothing
        numeric_cols = [n for n in names(df) if eltype(df[!, n]) <: Number || all(x -> tryparse(Float64, string(x)) !== nothing || ismissing(x), df[!, n])]
        mpcol = isnothing(mpcol) ? numeric_cols[1] : mpcol
        cbicol = isnothing(cbicol) ? numeric_cols[2] : cbicol
    end

    out = DataFrame(date = map(parse_date_col, df[!, dcol]), mp = df[!, mpcol], cbi = df[!, cbicol])
    dropmissing!(out)
    out.mp = parse.(Float64, string.(out.mp))
    out.cbi = parse.(Float64, string.(out.cbi))
    out.q = quarter_date.(out.date)
    qdf = combine(groupby(out, :q), :mp => sum => :mp_shock_jk, :cbi => sum => :cbi_shock_jk)

    if nrow(qdf) > 0
        sample_q = qdf.q[end]
        sample_m = filter(:q => ==(sample_q), out)
        println("JK aggregation check for $(sample_q): monthly_mp=$(sample_m.mp), qsum_mp=$(qdf[qdf.q .== sample_q, :mp_shock_jk][1])")
    end
    return qdf
end

function outermerge_on_q(dfs::Vector{DataFrame})
    out = dfs[1]
    for i in 2:length(dfs)
        out = outerjoin(out, dfs[i], on=:q)
    end
    sort!(out, :q)
    return out
end

function main()
    fred_ids = ["COMPNFB","IPDNBS","PCECTPI","GDPC1","UNRATE","HOANBS","ECIWAG","CES0500000003","CPIAUCSL","CPILFESL"]
    fred_dfs = [read_fred_series(s) for s in fred_ids]
    data = outermerge_on_q(vcat(fred_dfs, [read_kanzig_monthly(), read_frbsf_monthly(), read_jk_monthly()]))

    # Restrict to post-1994Q1 baseline overlap by default.
    data = filter(:q => >=(Date(1994, 3, 1)), data)

    CSV.write(joinpath(PROC_DIR, "quarterly_merged_unbalanced.csv"), data)

    required = [:COMPNFB, :IPDNBS, :PCECTPI, :GDPC1, :UNRATE, :oil_shock]
    keep = trues(nrow(data))
    for c in required
        if c in names(data)
            keep .&= .!ismissing.(data[!, c])
        end
    end
    balanced = data[keep, :]
    CSV.write(joinpath(PROC_DIR, "quarterly_balanced.csv"), balanced)

    meta = DataFrame(
        series=["oil_shock","mp_shock_frbsf","mp_shock_jk","cbi_shock_jk","UNRATE"],
        source=["Känzig","FRBSF","JK","JK","FRED"],
        quarterly_aggregation=["sum","sum","sum","sum","average"],
        sign_convention_target=["adverse supply > 0","contractionary > 0","contractionary > 0","information > 0","level"],
    )
    CSV.write(joinpath(PROC_DIR, "series_metadata.csv"), meta)
    println("Wrote processed datasets and series_metadata.csv")
end

main()
