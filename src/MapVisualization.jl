# Interactive route maps as standalone HTML (plotly.js, loaded from a CDN)

const PLOTLY_CDN = "https://cdn.jsdelivr.net/npm/plotly.js-dist-min@2.35.2/plotly.min.js"
const VEHICLE_COLORS = [
    "#4e79a7", "#f28e2b", "#59a14f", "#b07aa1", "#76b7b2",
    "#edc948", "#9c755f", "#ff9da7", "#bab0ac", "#86bcb6",
]

_hours(s) = ismissing(s) ? "–" : string(round(s / 3600; digits = 2), " h")

"""
    generate_route_map(result::DispatchResult, instance, output_html; title=result.method)
    generate_route_map(freight_results::DataFrame, vehicles::DataFrame, output_html; title="Freight Routes", show_failures=true)

Write an interactive HTML map. Each vehicle has its own colour; loaded legs
(pickup → delivery) are solid, empty legs (to pickup, back to base) dotted.
Circles are pickups, squares deliveries, diamonds vehicle bases, red crosses
unserved freights. `freight_results` is the table returned by the simulation
(it already contains the coordinates).
"""
function generate_route_map(
    freight_results::DataFrame,
    vehicles::Vector{Vehicle},
    output_html::AbstractString;
    title::AbstractString = "Freight Routes",
    subtitle::AbstractString = "",
    show_failures::Bool = true,
)
    traces = Any[]
    served = filter(r -> r.success, freight_results)
    for (j, v) in enumerate(vehicles)
        trips = sort(filter(r -> !ismissing(r.assigned_vehicle) && r.assigned_vehicle == v.id, served), :start_s)
        color = VEHICLE_COLORS[mod1(j, length(VEHICLE_COLORS))]
        group = v.id
        empty_lat, empty_lon = Union{Float64,Nothing}[], Union{Float64,Nothing}[]
        load_lat, load_lon = Union{Float64,Nothing}[], Union{Float64,Nothing}[]
        lat, lon = v.start_lat, v.start_lon
        for r in eachrow(trips)
            append!(empty_lat, [lat, r.pickup_lat, nothing]); append!(empty_lon, [lon, r.pickup_lon, nothing])
            append!(load_lat, [r.pickup_lat, r.delivery_lat, nothing]); append!(load_lon, [r.pickup_lon, r.delivery_lon, nothing])
            append!(empty_lat, [r.delivery_lat, v.base_lat, nothing]); append!(empty_lon, [r.delivery_lon, v.base_lon, nothing])
            lat, lon = v.base_lat, v.base_lon
        end
        label = "$(v.id) ($(nrow(trips)) trips)"
        push!(traces, (type = "scattergeo", mode = "lines", lat = load_lat, lon = load_lon, name = label,
            legendgroup = group, line = (color = color, width = 3), hoverinfo = "skip"))
        push!(traces, (type = "scattergeo", mode = "lines", lat = empty_lat, lon = empty_lon, name = label,
            legendgroup = group, showlegend = false, line = (color = color, width = 1.5, dash = "dot"), hoverinfo = "skip"))
        push!(traces, (type = "scattergeo", mode = "markers", lat = [v.base_lat], lon = [v.base_lon], name = label,
            legendgroup = group, showlegend = false, hoverinfo = "text",
            text = ["Base $(v.id)<br>capacity $(v.capacity_kg) kg, $(v.speed_km_per_hour) km/h"],
            marker = (symbol = "diamond", size = 13, color = color, line = (color = "#222", width = 1))))
        if nrow(trips) > 0
            hover = ["$(r.freight_id) → $(v.id)<br>$(r.weight_kg) kg<br>ready $(_hours(r.ready_s)), due $(_hours(r.due_s))<br>delivered $(_hours(r.delivered_s)), late $(_hours(r.lateness_s))"
                     for r in eachrow(trips)]
            push!(traces, (type = "scattergeo", mode = "markers", lat = trips.pickup_lat, lon = trips.pickup_lon,
                name = label, legendgroup = group, showlegend = false, hoverinfo = "text", text = hover,
                marker = (symbol = "circle", size = 9, color = color, line = (color = "#222", width = 1))))
            push!(traces, (type = "scattergeo", mode = "markers", lat = trips.delivery_lat, lon = trips.delivery_lon,
                name = label, legendgroup = group, showlegend = false, hoverinfo = "text", text = hover,
                marker = (symbol = [r.on_time ? "square" : "square-open" for r in eachrow(trips)], size = 9, color = color,
                    line = (color = color, width = 2))))
        end
    end
    failed = filter(r -> !r.success, freight_results)
    if show_failures && nrow(failed) > 0
        push!(traces, (type = "scattergeo", mode = "markers", lat = failed.pickup_lat, lon = failed.pickup_lon,
            name = "Unserved ($(nrow(failed)))", hoverinfo = "text",
            text = ["$(r.freight_id) unserved<br>$(r.weight_kg) kg" for r in eachrow(failed)],
            marker = (symbol = "x", size = 12, color = "#d62728")))
    end

    n_ok = nrow(served)
    heading = "$(title): $(n_ok)/$(nrow(freight_results)) freights served"
    isempty(subtitle) || (heading *= "<br><sub>$(subtitle)</sub>")
    layout = (
        title = (text = heading, x = 0.02),
        margin = (l = 0, r = 0, t = 60, b = 0),
        legend = (title = (text = "Vehicles"),),
        annotations = [(text = "solid = loaded · dotted = empty · ○ pickup · □ delivered on time · open □ late · ◇ base",
            showarrow = false, xref = "paper", yref = "paper", x = 0.02, y = 0.0, xanchor = "left", yanchor = "bottom",
            font = (size = 11, color = "#555"), bgcolor = "rgba(255,255,255,0.8)")],
        geo = (
            fitbounds = "locations",
            projection = (type = "mercator",),
            resolution = 50,
            showland = true, landcolor = "#f3f1ec",
            showcountries = true, countrycolor = "#b8b2a7",
            showsubunits = true, subunitcolor = "#d8d2c7",
            showocean = true, oceancolor = "#dde8f0",
            showlakes = false,
        ),
    )
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$(title)</title>
    <script src="$(PLOTLY_CDN)"></script>
    <style>html,body{margin:0;height:100%;font-family:system-ui,sans-serif;background:#fff}#map{width:100%;height:100vh}</style>
    </head>
    <body>
    <div id="map"></div>
    <script>
    Plotly.newPlot("map", $(JSON.json(traces)), $(JSON.json(layout)), {responsive: true});
    </script>
    </body>
    </html>
    """
    mkpath(dirname(abspath(output_html)))
    write(output_html, html)
    return output_html
end

generate_route_map(freight_results::DataFrame, vehicles::DataFrame, output_html::AbstractString; kw...) =
    generate_route_map(freight_results, _vehicles_from(vehicles), output_html; kw...)

function generate_route_map(r::DispatchResult, inst, output_html::AbstractString; title::AbstractString = r.method, kw...)
    k = r.kpis
    subtitle = "$(round(Int, k.total_distance_km)) km · on time $(k.n_on_time)/$(k.n_freights) · " *
               "lateness $(round(k.total_lateness_h; digits = 1)) h · objective $(round(Int, k.objective))"
    vehicles = inst isa DataFrame ? _vehicles_from(inst) : load_instance(inst).vehicles
    return generate_route_map(r.freight_results, vehicles, output_html; title = title, subtitle = subtitle, kw...)
end

_vehicles_from(vehicles::DataFrame) = load_instance(_empty_freights(), vehicles).vehicles
_empty_freights() = DataFrame(
    id = String[], weight_kg = Float64[], pickup_lat = Float64[], pickup_lon = Float64[],
    delivery_lat = Float64[], delivery_lon = Float64[], pickup_time = Float64[], delivery_time = Float64[],
)
