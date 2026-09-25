# Draw docs/assets/scalability.svg from docs/benchmark_scalability.csv.
#
#   julia --project=. scripts/scalability_chart.jl
#
# Mean solve time per instance size (log scale), one line per method. The SVG
# carries its own light/dark colours and a <title> tooltip on every point.

using CSV, DataFrames

function scalability_svg(csv_path::AbstractString, svg_path::AbstractString; time_limit = 60.0)
    df = CSV.read(csv_path, DataFrame)
    g = combine(groupby(df, :n_freights),
        :greedy_time_s => (x -> sum(x) / length(x)) => :greedy,
        :ls_time_s => (x -> sum(x) / length(x)) => :ls,
        :milp_time_s => (x -> sum(x) / length(x)) => :milp,
        :milp_proven_optimal => (x -> count(x)) => :proven,
        nrow => :runs)
    sort!(g, :n_freights)

    W, H = 720, 400
    left, right, top, bottom = 64, 120, 74, 52
    pw, ph = W - left - right, H - top - bottom
    xs = g.n_freights
    xmin, xmax = minimum(xs) - 3, maximum(xs) + 3
    ymin, ymax = -5, 2                      # 10 µs .. 100 s
    X(x) = left + (x - xmin) / (xmax - xmin) * pw
    Y(t) = top + (ymax - log10(max(t, 10.0^ymin))) / (ymax - ymin) * ph
    fmt(t) = t < 1e-3 ? "$(round(t * 1e6; digits = 0)) µs" : t < 1 ? "$(round(t * 1e3; digits = 1)) ms" : "$(round(t; digits = 1)) s"

    series = [
        (key = :greedy, label = "Best greedy rule", cls = "s1", marker = :circle),
        (key = :ls, label = "Local search", cls = "s2", marker = :square),
        (key = :milp, label = "MILP", cls = "s3", marker = :diamond),
    ]

    io = IOBuffer()
    print(io, """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $W $H" width="$W" height="$H" role="img" aria-labelledby="t d" font-family="system-ui, -apple-system, Segoe UI, sans-serif">
    <title id="t">Solve time versus number of freights</title>
    <desc id="d">Mean solve time on generated instances, log scale. Greedy stays in microseconds, local search in milliseconds, the MILP grows steeply and reaches its $(Int(time_limit)) s time limit on the largest instances. Data in docs/benchmark_scalability.csv.</desc>
    <style>
      .bg{fill:#fcfcfb} .grid{stroke:#e1e0d9;stroke-width:1} .axis{stroke:#c3c2b7;stroke-width:1}
      .ink{fill:#0b0b0b} .ink2{fill:#52514e} .muted{fill:#898781}
      .s1{stroke:#2a78d6;fill:#2a78d6} .s2{stroke:#eb6834;fill:#eb6834} .s3{stroke:#1baf7a;fill:#1baf7a}
      .ring{stroke:#fcfcfb} .limit{stroke:#898781;stroke-dasharray:4 4;stroke-width:1}
      @media (prefers-color-scheme: dark) {
        .bg{fill:#1a1a19} .grid{stroke:#2c2c2a} .axis{stroke:#383835}
        .ink{fill:#ffffff} .ink2{fill:#c3c2b7}
        .s1{stroke:#3987e5;fill:#3987e5} .s2{stroke:#d95926;fill:#d95926} .s3{stroke:#199e70;fill:#199e70}
        .ring{stroke:#1a1a19}
      }
    </style>
    <rect class="bg" width="$W" height="$H" rx="8"/>
    <text class="ink" x="$left" y="24" font-size="15" font-weight="600">Solve time vs. instance size</text>
    <text class="ink2" x="$left" y="40" font-size="12">Mean over $(g.runs[1]) generated instances per size · log scale</text>
    """)
    for e in ymin:ymax
        y = Y(10.0^e)
        label = e <= -4 ? "$(10^(e + 6)) µs" : e <= -1 ? "$(10^(e + 3)) ms" : e == 0 ? "1 s" : "$(10^e) s"
        print(io, """<line class="grid" x1="$left" x2="$(left + pw)" y1="$y" y2="$y"/>
        <text class="muted" x="$(left - 8)" y="$(y + 4)" font-size="11" text-anchor="end">$label</text>\n""")
    end
    print(io, """<line class="axis" x1="$left" x2="$(left + pw)" y1="$(top + ph)" y2="$(top + ph)"/>\n""")
    for x in xs
        print(io, """<text class="muted" x="$(X(x))" y="$(top + ph + 18)" font-size="11" text-anchor="middle">$x</text>\n""")
    end
    print(io, """<text class="ink2" x="$(left + pw / 2)" y="$(H - 10)" font-size="12" text-anchor="middle">Freights (vehicles = freights ÷ 4, min 2)</text>\n""")
    ly = Y(time_limit)
    print(io, """<line class="limit" x1="$left" x2="$(X(xs[end]))" y1="$ly" y2="$ly"/>
    <text class="muted" x="$(left + 4)" y="$(ly - 5)" font-size="11">MILP time limit ($(Int(time_limit)) s)</text>\n""")

    for s in series
        ys = g[!, s.key]
        pts = join(("$(X(x)),$(Y(t))" for (x, t) in zip(xs, ys)), " ")
        print(io, """<polyline class="$(s.cls)" style="fill:none" stroke-width="2" stroke-linejoin="round" points="$pts"/>\n""")
        for (k, (x, t)) in enumerate(zip(xs, ys))
            cx, cy = X(x), Y(t)
            tip = "$(s.label), $(x) freights: $(fmt(t))" * (s.key == :milp ? " · optimal $(g.proven[k])/$(g.runs[k])" : "")
            shape = s.marker == :circle ? """<circle cx="$cx" cy="$cy" r="4.5"/>""" :
                    s.marker == :square ? """<rect x="$(cx - 4)" y="$(cy - 4)" width="8" height="8" rx="1"/>""" :
                    """<path d="M $cx $(cy - 5.5) L $(cx + 5.5) $cy L $cx $(cy + 5.5) L $(cx - 5.5) $cy Z"/>"""
            print(io, """<g class="$(s.cls)"><g class="ring" stroke-width="2">$shape</g><title>$tip</title></g>\n""")
        end
    end
    # direct labels at the line ends, in text ink, nudged apart so they never overlap
    ends = sort([(Y(g[end, s.key]), s.label) for s in series]; by = first)
    label_y = [e[1] for e in ends]
    for k in 2:length(label_y)
        label_y[k] = max(label_y[k], label_y[k-1] + 15)
    end
    for (k, (_, label)) in enumerate(ends)
        print(io, """<text class="ink2" x="$(X(xs[end]) + 12)" y="$(label_y[k] + 4)" font-size="12">$(label)</text>\n""")
    end
    # legend (one row above the plot)
    for (k, s) in enumerate(series)
        y = 58
        x = left + (k - 1) * 150
        print(io, """<line class="$(s.cls)" x1="$x" x2="$(x + 18)" y1="$y" y2="$y" stroke-width="2"/>
        <text class="ink2" x="$(x + 24)" y="$(y + 4)" font-size="12">$(s.label)</text>\n""")
    end
    print(io, "</svg>\n")
    mkpath(dirname(svg_path))
    write(svg_path, take!(io))
    return svg_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    docs = joinpath(@__DIR__, "..", "docs")
    println(scalability_svg(joinpath(docs, "benchmark_scalability.csv"), joinpath(docs, "assets", "scalability.svg")))
end
