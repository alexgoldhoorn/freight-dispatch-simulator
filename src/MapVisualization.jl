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
    failed_freight = filter(
        row -> row.success == false || row.assigned_vehicle === nothing,
        freight_df,
    )
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

    # Build informative title
    n_total = nrow(freight_df)
    n_success = nrow(successful_freight)
    n_failed = nrow(failed_freight)
    full_title = "$title: $n_success/$n_total freights assigned"
    if n_failed > 0
        full_title *= " ($n_failed failed)"
    end

    # Initialize plot with coastlines
    fig = plot(
        title = full_title,
        legend = :outerright,
        size = (1400, 900),
        showaxis = true,
        grid = true,
        xlabel = "Longitude",
        ylabel = "Latitude",
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

            # Get freight ID from appropriate column
            freight_id = hasproperty(freight_row, :freight_id) ? freight_row.freight_id : freight_row.id
            hover_text = "Vehicle: $vehicle_id\nFreight: $(freight_id)\n$weight_info\n$distance_info\n$time_info"

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

    # Add pickup and delivery markers (color-coded by vehicle)
    if !isempty(successful_freight)
        # Group by vehicle and add markers
        for vehicle_id in unique_vehicles
            vehicle_freight = filter(
                row -> row.assigned_vehicle == vehicle_id && row.success == true,
                freight_df,
            )

            if isempty(vehicle_freight)
                continue
            end

            vehicle_color = vehicle_colors[vehicle_id]

            # Pickup markers (circles) for this vehicle
            pickup_lats = vehicle_freight.pickup_lat
            pickup_lons = vehicle_freight.pickup_lon
            freight_ids = [hasproperty(row, :freight_id) ? row.freight_id : row.id for row in eachrow(vehicle_freight)]
            pickup_hover = ["Vehicle $vehicle_id\nPickup: $fid" for fid in freight_ids]

            scatter!(
                fig,
                pickup_lons,
                pickup_lats,
                markershape = :circle,
                markersize = 10,
                markercolor = vehicle_color,
                markerstrokewidth = 2,
                markerstrokecolor = :black,
                label = "",  # Don't add to legend (already have route line)
                hover = pickup_hover,
                alpha = 0.8,
            )

            # Delivery markers (squares) for this vehicle
            delivery_lats = vehicle_freight.delivery_lat
            delivery_lons = vehicle_freight.delivery_lon
            delivery_hover = ["Vehicle $vehicle_id\nDelivery: $fid" for fid in freight_ids]

            scatter!(
                fig,
                delivery_lons,
                delivery_lats,
                markershape = :square,
                markersize = 10,
                markercolor = vehicle_color,
                markerstrokewidth = 2,
                markerstrokecolor = :black,
                label = "",  # Don't add to legend
                hover = delivery_hover,
                alpha = 0.8,
            )
        end

        # Add legend entries for marker types (one-time, not per vehicle)
        # Use dummy plots just for legend
        scatter!(
            fig,
            [NaN],
            [NaN],
            markershape = :circle,
            markersize = 8,
            markercolor = :lightgray,
            markerstrokewidth = 2,
            markerstrokecolor = :black,
            label = "⚫ Pickup",
        )
        scatter!(
            fig,
            [NaN],
            [NaN],
            markershape = :square,
            markersize = 8,
            markercolor = :lightgray,
            markerstrokewidth = 2,
            markerstrokecolor = :black,
            label = "■ Delivery",
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
            freight_ids = [hasproperty(row, :freight_id) ? row.freight_id : row.id for row in eachrow(failed_freight)]
            failed_hover = ["⚠️ UNASSIGNED: $fid\nNo vehicle available" for fid in freight_ids]

            scatter!(
                fig,
                failed_lons,
                failed_lats,
                markershape = :xcross,
                markersize = 12,
                markercolor = :red,
                markerstrokewidth = 3,
                label = "❌ Failed/Unassigned",
                hover = failed_hover,
                alpha = 0.9,
            )
        end
    end

    # Add vehicle base locations (color-coded by vehicle)
    if !isempty(vehicle_df)
        for vehicle_row in eachrow(vehicle_df)
            vehicle_id = vehicle_row.id
            base_lat =
                hasproperty(vehicle_row, :base_lat) && !ismissing(vehicle_row.base_lat) ?
                vehicle_row.base_lat : vehicle_row.start_lat
            base_lon =
                hasproperty(vehicle_row, :base_lon) && !ismissing(vehicle_row.base_lon) ?
                vehicle_row.base_lon : vehicle_row.start_lon

            # Get vehicle color if it has assignments, otherwise use gray
            vehicle_color = haskey(vehicle_colors, vehicle_id) ?
                           vehicle_colors[vehicle_id] : RGB(0.7, 0.7, 0.7)

            scatter!(
                fig,
                [base_lon],
                [base_lat],
                markershape = :star5,
                markersize = 14,
                markercolor = vehicle_color,
                markerstrokewidth = 2,
                markerstrokecolor = :black,
                label = "",  # Don't add to legend
                hover = ["⭐ Base: $vehicle_id"],
                alpha = 0.9,
            )
        end

        # Add legend entry for bases
        scatter!(
            fig,
            [NaN],
            [NaN],
            markershape = :star5,
            markersize = 10,
            markercolor = :gold,
            markerstrokewidth = 2,
            markerstrokecolor = :black,
            label = "⭐ Base",
        )
    end

    # Save the interactive HTML file
    savefig(fig, output_html)

    println("Interactive map saved to: $output_html")

    return nothing
end
