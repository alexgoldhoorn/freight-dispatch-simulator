# Vehicle timeline (Gantt) charts as standalone SVG

"""
    generate_timeline(results, instance, output_svg; title="Vehicle timelines")

Write an SVG with one panel per `DispatchResult` (e.g. greedy vs MILP), stacked
on a shared time axis. Each row is a vehicle. A trip is drawn as three
segments: driving empty to the pickup, carrying the load, and returning to base.
Ticks mark deadlines; the loaded segment is red when the freight was
delivered after its deadline. The SVG follows light/dark mode and
has a tooltip on every trip.
"""
function generate_timeline(results::AbstractVector{DispatchResult}, inst, output_svg::AbstractString; title::AbstractString = "Vehicle timelines")
    inst = load_instance(inst)
    vehicles = inst.vehicles
    m = length(vehicles)
    W = 960
    left, right = 70, 24
    row_h, bar_h = 26, 14
    panel_head = 44
    pw = W - left - right
    tmax = maximum(r.kpis.makespan_h for r in results) * 3600
    tmax = tmax > 0 ? tmax : 3600.0
    step_h = _nice_step(tmax / 3600)
    xmax = ceil(tmax / 3600 / step_h) * step_h * 3600
    X(t) = left + t / xmax * pw
    fmt_h(s) = string(round(s / 3600; digits = 1), " h")

    top = 84
    panel_h = panel_head + m * row_h + 8
    H = top + length(results) * panel_h + 44

    io = IOBuffer()
    print(io, """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $W $H" width="$W" height="$H" role="img" aria-labelledby="tt td" font-family="system-ui, -apple-system, Segoe UI, sans-serif">
    <title id="tt">$(title)</title>
    <desc id="td">One row per vehicle. Light segments: driving empty to pickup and back to base; dark segments: carrying a freight that arrives on time; red segments: carrying a freight that arrives after its deadline.</desc>
    <style>
      .bg{fill:#fcfcfb} .grid{stroke:#e1e0d9;stroke-width:1} .axis{stroke:#c3c2b7;stroke-width:1}
      .ink{fill:#0b0b0b} .ink2{fill:#52514e} .muted{fill:#898781}
      .empty{fill:#86b6ef} .loaded{fill:#2a78d6} .late{fill:#d03b3b} .due{stroke:#52514e;stroke-width:1.5}
      .gap{stroke:#fcfcfb;stroke-width:2} .band{fill:#f3f2ee}
      @media (prefers-color-scheme: dark) {
        .bg{fill:#1a1a19} .grid{stroke:#2c2c2a} .axis{stroke:#383835}
        .ink{fill:#ffffff} .ink2{fill:#c3c2b7}
        .empty{fill:#1c5cab} .loaded{fill:#5598e7} .due{stroke:#c3c2b7} .gap{stroke:#1a1a19} .band{fill:#222220}
      }
    </style>
    <rect class="bg" width="$W" height="$H" rx="8"/>
    <text class="ink" x="$left" y="26" font-size="16" font-weight="600">$(title)</text>
    """)
    # legend
    lx = left
    for (cls, label, w) in (("empty", "driving empty (to pickup, back to base)", 270), ("loaded", "carrying, on time", 140), ("late", "carrying, delivered late", 180))
        print(io, """<rect class="$cls" x="$lx" y="$(48 - bar_h / 2)" width="18" height="$bar_h" rx="2"/><text class="ink2" x="$(lx + 24)" y="52" font-size="12">$label</text>\n""")
        lx += w
    end
    print(io, """<line class="due" x1="$(lx + 4)" x2="$(lx + 4)" y1="41" y2="55"/><text class="ink2" x="$(lx + 12)" y="52" font-size="12">deadline</text>\n""")

    for (p, r) in enumerate(results)
        y0 = top + (p - 1) * panel_h
        k = r.kpis
        print(io, """<text class="ink" x="$left" y="$(y0 + 16)" font-size="14" font-weight="600">$(_panel_title(r))</text>
        <text class="ink2" x="$left" y="$(y0 + 34)" font-size="12">objective $(round(Int, k.objective)) · $(round(Int, k.total_distance_km)) km · on time $(k.n_on_time)/$(k.n_freights) · $(round(k.total_lateness_h; digits = 1)) h late in total · done after $(round(k.makespan_h; digits = 1)) h</text>\n""")
        gy = y0 + panel_head
        for t in 0:step_h:(xmax / 3600)
            x = X(t * 3600)
            print(io, """<line class="grid" x1="$x" x2="$x" y1="$gy" y2="$(gy + m * row_h)"/>\n""")
        end
        fr = r.freight_results
        for (j, v) in enumerate(vehicles)
            ry = gy + (j - 1) * row_h
            by = ry + (row_h - bar_h) / 2 - 2
            iseven(j) && print(io, """<rect class="band" x="$left" y="$ry" width="$pw" height="$row_h" opacity="0.6"/>\n""")
            print(io, """<text class="ink2" x="$(left - 10)" y="$(ry + row_h / 2 + 2)" font-size="12" text-anchor="end">$(v.id)</text>\n""")
            trips = sort(filter(x -> x.success && x.assigned_vehicle == v.id, fr), :start_s)
            for t in eachrow(trips)
                late = t.lateness_s > 0
                tip = "$(t.freight_id) on $(v.id): start $(fmt_h(t.start_s)), pickup $(fmt_h(t.pickup_s)), delivered $(fmt_h(t.delivered_s)) (deadline $(fmt_h(t.due_s)))" *
                      (late ? ", $(fmt_h(t.lateness_s)) late" : ", on time")
                segs = (("empty", t.start_s, t.pickup_s), (late ? "late" : "loaded", t.pickup_s, t.delivered_s), ("empty", t.delivered_s, t.back_at_base_s))
                print(io, "<g><title>$(tip)</title>")
                for (cls, a, b) in segs
                    b > a || continue
                    print(io, """<rect class="$cls" x="$(X(a))" y="$by" width="$(max(X(b) - X(a), 0.5))" height="$bar_h"/>""")
                end
                # surface gap marks the boundary between consecutive trips
                print(io, """<line class="gap" x1="$(X(t.start_s))" x2="$(X(t.start_s))" y1="$by" y2="$(by + bar_h)"/>""")
                if t.due_s <= xmax
                    print(io, """<line class="due" x1="$(X(t.due_s))" x2="$(X(t.due_s))" y1="$(by - 3)" y2="$(by + bar_h + 3)"/>""")
                end
                print(io, "</g>\n")
            end
        end
        print(io, """<line class="axis" x1="$left" x2="$(left + pw)" y1="$(gy + m * row_h)" y2="$(gy + m * row_h)"/>\n""")
    end
    ay = top + length(results) * panel_h
    for t in 0:step_h:(xmax / 3600)
        print(io, """<text class="muted" x="$(X(t * 3600))" y="$(ay + 6)" font-size="11" text-anchor="middle">$(Int(t))</text>\n""")
    end
    print(io, """<text class="ink2" x="$(left + pw / 2)" y="$(ay + 26)" font-size="12" text-anchor="middle">Hours since the first freight was released</text>\n</svg>\n""")
    mkpath(dirname(abspath(output_svg)))
    write(output_svg, take!(io))
    return output_svg
end

function _panel_title(r::DispatchResult)
    r.method in first.(GREEDY_STRATEGIES) && return "Greedy · $(r.method) rule"
    r.method == "MILP" && return get(r.info, :proven_optimal, false) ? "MILP · proven optimal" :
           "MILP · best found within the time limit"
    return r.method
end

function _nice_step(span_h)
    for s in (1, 2, 3, 6, 12, 24, 48)
        span_h / s <= 12 && return s
    end
    return 96
end
