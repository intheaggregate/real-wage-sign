using CSV
using DataFrames
using Dates
using Downloads
using HTTP
using JSON3
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RAW_DIR = joinpath(ROOT, "data", "raw")
const TABLE_DIR = joinpath(ROOT, "output", "tables")
const PROVENANCE_PATH = joinpath(RAW_DIR, "provenance_manifest.csv")

mkpath(RAW_DIR)
mkpath(TABLE_DIR)

function sha256_file(path::AbstractString)
    open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function append_provenance!(rows::DataFrame, source::String, url::String, localpath::String; vintage_tag::String="")
    push!(rows, (
        source=source,
        url=url,
        downloaded_at_utc=string(Dates.now(Dates.UTC)),
        local_filepath=localpath,
        sha256=sha256_file(localpath),
        vintage_tag=vintage_tag,
    ))
end

function download_with_fallback(url::String, dest::String; source::String, fallback_note::String="")
    try
        Downloads.download(url, dest)
        return (success=true, msg="ok")
    catch err
        @warn "Download failed" source url err
        if !isempty(fallback_note)
            @info fallback_note
        end
        return (success=false, msg=string(err))
    end
end

function latest_kanzig_vintage()
    api_url = "https://api.github.com/repos/dkaenzig/oilsupplynews/contents/"
    response = HTTP.get(api_url)
    files = JSON3.read(String(response.body))
    rx = r"oilSupplyNewsShocks_(\d{4})M(\d{1,2})\.xlsx"

    candidates = NamedTuple[]
    for item in files
        name = String(item["name"])
        m = match(rx, name)
        isnothing(m) && continue
        year = parse(Int, m.captures[1])
        month = parse(Int, m.captures[2])
        push!(candidates, (name=name, year=year, month=month, download_url=String(item["download_url"])))
    end
    isempty(candidates) && error("No Känzig vintage files found at $api_url")

    sorted = sort(candidates, by=x -> (x.year, x.month), rev=true)
    @info "Top Känzig vintage candidates" top3=first(sorted, min(3, length(sorted)))
    return first(sorted)
end

function download_oil_shock!(rows::DataFrame)
    v = latest_kanzig_vintage()
    dest = joinpath(RAW_DIR, "oilSupplyNewsShocks_latest.xlsx")
    result = download_with_fallback(v.download_url, dest;
        source="kanzig_oil",
        fallback_note="Manually place latest oilSupplyNewsShocks_YYYYMmm.xlsx in data/raw and rerun.")
    result.success || return false
    append_provenance!(rows, "kanzig_oil", v.download_url, dest; vintage_tag=v.name)
    true
end

function download_frbsf_mp!(rows::DataFrame)
    url = "https://www.frbsf.org/wp-content/uploads/monetary-policy-surprises-data.xlsx"
    dest = joinpath(RAW_DIR, "monetary-policy-surprises-data.xlsx")
    result = download_with_fallback(url, dest;
        source="frbsf_mp",
        fallback_note="If FRBSF blocks direct access, manually download the file to data/raw/monetary-policy-surprises-data.xlsx.")
    result.success || return false
    append_provenance!(rows, "frbsf_mp", url, dest)
    true
end

function download_jk_mpinfo!(rows::DataFrame)
    url = "https://raw.githubusercontent.com/marekjarocinski/jkshocks_update_fed/main/shocks_fed_jk_m.csv"
    dest = joinpath(RAW_DIR, "shocks_fed_jk_m.csv")
    result = download_with_fallback(url, dest;
        source="jk_mpinfo",
        fallback_note="Manually place shocks_fed_jk_m.csv in data/raw and rerun.")
    result.success || return false
    append_provenance!(rows, "jk_mpinfo", url, dest)
    true
end

function download_fred_series!(rows::DataFrame; series_ids = ["COMPNFB","IPDNBS","PCECTPI","GDPC1","UNRATE","HOANBS","ECIWAG","CES0500000003","CPIAUCSL","CPILFESL"])
    local fred_ok, Fred
    fred_ok = false
    try
        @eval using FredData
        Fred = FredData
        fred_ok = true
    catch err
        @warn "FredData.jl unavailable; skipping FRED download" err
        return false
    end

    api_key = get(ENV, "FRED_API_KEY", "")
    if isempty(api_key)
        @warn "FRED_API_KEY is not set; skipping FRED download."
        return false
    end

    f = Fred.Fred(api_key)
    for sid in series_ids
        out = joinpath(RAW_DIR, "fred_$(sid).csv")
        try
            s = Fred.get_data(f, sid)
            CSV.write(out, DataFrame(s))
            append_provenance!(rows, "fred", "fred://$sid", out)
        catch err
            @warn "Could not download FRED series" sid err
        end
    end
    return true
end

function write_provenance(rows::DataFrame)
    if isfile(PROVENANCE_PATH)
        old = CSV.read(PROVENANCE_PATH, DataFrame)
        rows = vcat(old, rows)
    end
    CSV.write(PROVENANCE_PATH, rows)
end

function main()
    rows = DataFrame(source=String[], url=String[], downloaded_at_utc=String[], local_filepath=String[], sha256=String[], vintage_tag=String[])

    ok_oil = download_oil_shock!(rows)
    ok_frb = download_frbsf_mp!(rows)
    ok_jk = download_jk_mpinfo!(rows)
    ok_fred = download_fred_series!(rows)

    write_provenance(rows)

    summary = DataFrame(dataset=["kanzig_oil","frbsf_mp","jk_mpinfo","fred"],
        downloaded=[ok_oil, ok_frb, ok_jk, ok_fred])
    CSV.write(joinpath(TABLE_DIR, "download_status.csv"), summary)
    println("Download status written to output/tables/download_status.csv")
end

main()
