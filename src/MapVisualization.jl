using Plots
using DataFrames
using Colors

"""
    generate_route_map(
        freight_df::DataFrame,
        vehicle_df::DataFrame,
        output_html::AbstractString;
        show_failures::Bool = true,
        title::AbstractString = "Freight Routes"
    )::Nothing

Generate an interactive HTML map showing freight delivery routes for vehicles.

# Arguments
- `freight_df::DataFrame`: DataFrame containing freight information with columns:
  - `id`: Freight ID
  - `assigned_vehicle`: Vehicle ID (or `nothing` for unassigned)
  - `pickup_lat`, `pickup_lon`: Pickup coordinates
  - `delivery_lat`, `delivery_lon`: Delivery coordinates
  - `success`: Boolean indicating if freight was successfully assigned
  - `distance_km`: Total distance traveled (optional)
  - Additional columns for hover information (weight, time, etc.)

- `vehicle_df::DataFrame`: DataFrame containing vehicle information with columns:
  - `id`: Vehicle ID
  - `start_lat`, `start_lon`: Starting coordinates
  - `base_lat`, `base_lon`: Base coordinates (optional, defaults to start)

- `output_html::AbstractString`: Path to output HTML file

# Optional Arguments
- `show_failures::Bool = true`: Whether to show unassigned freight
- `title::AbstractString = "Freight Routes"`: Map title

# Returns
- `Nothing`: Saves interactive HTML map to `output_html`
"""
# Generate interactive route map with PlotlyJS backend
function generate_route_map(
    freight_df::DataFrame,
    vehicle_df::DataFrame,
    output_html::AbstractString;
    show_failures::Bool = true,
    title::AbstractString = "Freight Routes",
)::Nothing

    # Set PlotlyJS backend for interactive plots
    plotlyjs()

    # Get unique vehicles that have assigned freight
    successful_freight =
        filter(row -> row.success == true && row.assigned_vehicle !== nothing, freight_df)
    unique_vehicles = unique(successful_freight.assigned_vehicle)

    # Create a color palette with enough colors for all vehicles
    n_vehicles = length(unique_vehicles)
    if n_vehicles > 0
        palette = distinguishable_colors(
            n_vehicles,
            [RGB(1, 1, 1), RGB(0, 0, 0)],
            dropseed = true,
        )
    else
        palette = [RGB(0.2, 0.6, 0.8)]  # Default blue color
    end

    # Create consistent vehicle→color mapping
    vehicle_colors = Dict(zip(unique_vehicles, palette))

    # Initialize plot with coastlines
    fig = plot(
        title = title,
        legend = :outertopright,
        size = (1200, 800),
        showaxis = false,
        grid = false,
    )

    # Add coastlines if possible (this is a basic implementation)
    # Note: For proper coastlines, you'd need additional geographic data

    # Process each vehicle
    for (vehicle_idx, vehicle_id) in enumerate(unique_vehicles)
        vehicle_color = vehicle_colors[vehicle_id]

        # Get vehicle information
        vehicle_info = filter(row -> row.id == vehicle_id, vehicle_df)
        if isempty(vehicle_info)
            continue
        end

        vehicle_row = first(vehicle_info)
        start_lat = vehicle_row.start_lat
        start_lon = vehicle_row.start_lon

        # Get base coordinates (default to start if not provided)
        base_lat =
            hasproperty(vehicle_row, :base_lat) && !ismissing(vehicle_row.base_lat) ?
            vehicle_row.base_lat : start_lat
        base_lon =
            hasproperty(vehicle_row, :base_lon) && !ismissing(vehicle_row.base_lon) ?
            vehicle_row.base_lon : start_lon

        # Get all freight assigned to this vehicle
        vehicle_freight = filter(
            row -> row.assigned_vehicle == vehicle_id && row.success == true,
            freight_df,
        )

        if isempty(vehicle_freight)
            continue
        end

        # Build route coordinates and hover text for this vehicle
        route_lats = Float64[]
        route_lons = Float64[]
        hover_texts = String[]

        for freight_row in eachrow(vehicle_freight)
            # Route: start → pickup → delivery → base
            route_segment_lats =
                [start_lat, freight_row.pickup_lat, freight_row.delivery_lat, base_lat]
            route_segment_lons =
                [start_lon, freight_row.pickup_lon, freight_row.delivery_lon, base_lon]

            # Create hover text with freight and vehicle information
            weight_info =
                hasproperty(freight_row, :weight_kg) ?
                "Weight: $(freight_row.weight_kg)kg" : ""
            distance_info =
                hasproperty(freight_row, :distance_km) ?
                "Distance: $(round(freight_row.distance_km, digits=2))km" : ""
            time_info =
                hasproperty(freight_row, :completion_time) ?
                "Completion: $(round(freight_row.completion_time, digits=2))s" : ""

            hover_text = "Vehicle: $vehicle_id\nFreight: $(freight_row.id)\n$weight_info\n$distance_info\n$time_info"

            # Add route coordinates
            append!(route_lats, route_segment_lats)
            append!(route_lons, route_segment_lons)

            # Add hover text for each point in the route
            append!(hover_texts, fill(hover_text, length(route_segment_lats)))

            # Add separator (NaN) between routes to create separate line segments
            if freight_row !== last(vehicle_freight)
                push!(route_lats, NaN)
                push!(route_lons, NaN)
                push!(hover_texts, "")
            end
        end

        # Plot the route for this vehicle
        plot!(
            fig,
            route_lons,
            route_lats,
            seriestype = :path,
            color = vehicle_color,
            linewidth = 2,
            alpha = 0.7,
            label = "Vehicle $vehicle_id",
            hover = hover_texts,
        )
    end

    # Add pickup and delivery markers
    if !isempty(successful_freight)
        # Pickup markers (circles)
        pickup_lats = successful_freight.pickup_lat
        pickup_lons = successful_freight.pickup_lon
        pickup_hover = ["Pickup: $(row.id)" for row in eachrow(successful_freight)]

        scatter!(
            fig,
            pickup_lons,
            pickup_lats,
            markershape = :circle,
            markersize = 6,
            markercolor = :green,
            markerstrokewidth = 1,
            markerstrokecolor = :darkgreen,
            label = "Pickup Points",
            hover = pickup_hover,
        )

        # Delivery markers (squares)
        delivery_lats = successful_freight.delivery_lat
        delivery_lons = successful_freight.delivery_lon
        delivery_hover = ["Delivery: $(row.id)" for row in eachrow(successful_freight)]

        scatter!(
            fig,
            delivery_lons,
            delivery_lats,
            markershape = :square,
            markersize = 6,
            markercolor = :blue,
            markerstrokewidth = 1,
            markerstrokecolor = :darkblue,
            label = "Delivery Points",
            hover = delivery_hover,
        )
    end

    # Add failed freight markers if requested
    if show_failures
        failed_freight = filter(
            row -> row.success == false || row.assigned_vehicle === nothing,
            freight_df,
        )

        if !isempty(failed_freight)
            # Show failed freight at pickup locations
            failed_lats = failed_freight.pickup_lat
            failed_lons = failed_freight.pickup_lon
            failed_hover = ["UNASSIGNED: $(row.id)" for row in eachrow(failed_freight)]

            scatter!(
                fig,
                failed_lons,
                failed_lats,
                markershape = :x,
                markersize = 8,
                markercolor = :red,
                markerstrokewidth = 2,
                label = "Failed Freight",
                hover = failed_hover,
            )
        end
    end

    # Add vehicle base locations
    if !isempty(vehicle_df)
        base_lats = Float64[]
        base_lons = Float64[]
        base_hover = String[]

        for vehicle_row in eachrow(vehicle_df)
            base_lat =
                hasproperty(vehicle_row, :base_lat) && !ismissing(vehicle_row.base_lat) ?
                vehicle_row.base_lat : vehicle_row.start_lat
            base_lon =
                hasproperty(vehicle_row, :base_lon) && !ismissing(vehicle_row.base_lon) ?
                vehicle_row.base_lon : vehicle_row.start_lon

            push!(base_lats, base_lat)
            push!(base_lons, base_lon)
            push!(base_hover, "Base: $(vehicle_row.id)")
        end

        scatter!(
            fig,
            base_lons,
            base_lats,
            markershape = :diamond,
            markersize = 8,
            markercolor = :purple,
            markerstrokewidth = 1,
            markerstrokecolor = :darkmagenta,
            label = "Vehicle Bases",
            hover = base_hover,
        )
    end

    # Save the interactive HTML file
    savefig(fig, output_html)

    println("Interactive map saved to: $output_html")

    return nothing
end
