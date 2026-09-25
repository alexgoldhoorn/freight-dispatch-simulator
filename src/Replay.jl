# Animated side-by-side replay of simulation runs (standalone HTML, plotly.js)

const REPLAY_VEHICLE_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
const REPLAY_OVERFLOW_COLOR = "#898781"   # vehicles beyond the 8 categorical slots

function _replay_payload(r::DispatchResult, inst::Instance)
    vid = Dict(v.id => j for (j, v) in enumerate(inst.vehicles))
    fr = r.freight_results
    vehicles = map(enumerate(inst.vehicles)) do (j, v)
        legs = Vector{Vector{Float64}}()
        lat, lon = v.start_lat, v.start_lon
        for t in eachrow(sort(filter(x -> x.success && x.assigned_vehicle == v.id, fr), :start_s))
            push!(legs, [t.start_s, t.pickup_s, lat, lon, t.pickup_lat, t.pickup_lon, 0])
            push!(legs, [t.pickup_s, t.delivered_s, t.pickup_lat, t.pickup_lon, t.delivery_lat, t.delivery_lon, 1])
            push!(legs, [t.delivered_s, t.back_at_base_s, t.delivery_lat, t.delivery_lon, v.base_lat, v.base_lon, 0])
            lat, lon = v.base_lat, v.base_lon
        end
        (id = v.id, color = j <= length(REPLAY_VEHICLE_COLORS) ? REPLAY_VEHICLE_COLORS[j] : REPLAY_OVERFLOW_COLOR,
         start = [v.start_lat, v.start_lon], base = [v.base_lat, v.base_lon],
         km_per_s = v.speed_km_per_hour / 3600, legs = legs)
    end
    freights = [
        (id = t.freight_id, ready = t.ready_s, due = t.due_s,
         pick = t.success ? t.pickup_s : nothing, deliv = t.success ? t.delivered_s : nothing,
         v = t.success ? vid[t.assigned_vehicle] - 1 : -1,
         p = [t.pickup_lat, t.pickup_lon], d = [t.delivery_lat, t.delivery_lon])
        for t in eachrow(fr)
    ]
    title = r.method in first.(GREEDY_STRATEGIES) ? "Greedy · $(r.method) rule" :
            r.method == "MILP" ? "MILP" : r.method
    return (title = title, vehicles = vehicles, freights = freights)
end

"""
    generate_replay(results, instance, output_html; title="Dispatch replay")

Write an HTML page that animates one or more `DispatchResult`s side by side on a
shared clock: vehicles move along their trips, freights appear at release
(open circle), turn red when their deadline passes before delivery, and end as
a green (on time) or red (late) square at the delivery point. Counters for
km, deliveries and lateness update as the clock runs. Play/pause and a time
slider are included; `window.renderAt(t_seconds)` draws one frame (used to
export a GIF).
"""
function generate_replay(results::AbstractVector{DispatchResult}, inst, output_html::AbstractString; title::AbstractString = "Dispatch replay")
    inst = load_instance(inst)
    lats = vcat([f.pickup_lat for f in inst.freights], [f.delivery_lat for f in inst.freights], [v.base_lat for v in inst.vehicles], [v.start_lat for v in inst.vehicles])
    lons = vcat([f.pickup_lon for f in inst.freights], [f.delivery_lon for f in inst.freights], [v.base_lon for v in inst.vehicles], [v.start_lon for v in inst.vehicles])
    pad_lat = max(0.3, 0.12 * (maximum(lats) - minimum(lats)))
    pad_lon = max(0.3, 0.12 * (maximum(lons) - minimum(lons)))
    tmax = maximum(maximum(skipmissing(r.freight_results.back_at_base_s); init = 0.0) for r in results)
    data = (
        title = title,
        tmax = tmax,
        lat = [minimum(lats) - pad_lat, maximum(lats) + pad_lat],
        lon = [minimum(lons) - pad_lon, maximum(lons) + pad_lon],
        runs = [_replay_payload(r, inst) for r in results],
    )
    html = replace(REPLAY_TEMPLATE, "__PLOTLY__" => PLOTLY_CDN, "__TITLE__" => title, "__DATA__" => JSON.json(data))
    mkpath(dirname(abspath(output_html)))
    write(output_html, html)
    return output_html
end

const REPLAY_TEMPLATE = raw"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<script src="__PLOTLY__"></script>
<style>
  :root { --bg:#fcfcfb; --ink:#0b0b0b; --ink2:#52514e; --muted:#898781; --line:#e1e0d9; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); font-family:system-ui,-apple-system,"Segoe UI",sans-serif; }
  header { display:flex; align-items:baseline; gap:16px; padding:14px 20px 0; flex-wrap:wrap; }
  h1 { font-size:18px; margin:0; font-weight:650; }
  #clock { font-variant-numeric:tabular-nums; font-size:18px; font-weight:650; margin-left:auto; }
  .legend { color:var(--ink2); font-size:12px; padding:4px 20px 0; display:flex; gap:16px; flex-wrap:wrap; align-items:center; }
  .sym { display:inline-block; width:10px; height:10px; margin-right:5px; vertical-align:-1px; }
  #map { width:100%; height:calc(100vh - 128px); min-height:420px; }
  .controls { display:flex; gap:12px; align-items:center; padding:0 20px 12px; }
  button { font:inherit; font-size:13px; padding:5px 14px; border:1px solid var(--line); background:#fff; border-radius:6px; cursor:pointer; color:var(--ink); }
  input[type=range] { flex:1; }
  body.capture .controls { display:none; }
  body.capture #map { height:calc(100vh - 76px); }
</style>
</head>
<body>
<header><h1 id="title"></h1><div id="clock"></div></header>
<div class="legend">
  <span><span class="sym" style="border:2px solid #52514e;border-radius:50%"></span>waiting for pickup</span>
  <span><span class="sym" style="border:2px solid #d03b3b;border-radius:50%"></span>waiting, past deadline</span>
  <span><span class="sym" style="background:#0ca30c"></span>delivered on time</span>
  <span><span class="sym" style="background:#d03b3b"></span>delivered late</span>
  <span>● vehicle (bigger when loaded) · thin line = route driven so far</span>
</div>
<div id="map"></div>
<div class="controls"><button id="play">Pause</button><input id="slider" type="range" min="0" max="1000" value="0"><span id="speed" style="color:var(--muted);font-size:12px"></span></div>
<script>
const D = __DATA__;
const GOOD = "#0ca30c", LATE = "#d03b3b", WAIT = "#52514e";
document.getElementById("title").textContent = D.title;
if (new URLSearchParams(location.search).has("capture")) document.body.classList.add("capture");

function hhmm(s) {
  const h = s / 3600, d = Math.floor(h / 24), r = h - 24 * d;
  const hh = Math.floor(r), mm = Math.floor((r - hh) * 60);
  return `Day ${d + 1} · ${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}

function position(v, t) {
  let last = v.start;
  for (const L of v.legs) {
    if (t < L[0]) return {p: last, loaded: false};
    if (t <= L[1]) {
      const f = L[1] > L[0] ? (t - L[0]) / (L[1] - L[0]) : 1;
      return {p: [L[2] + f * (L[4] - L[2]), L[3] + f * (L[5] - L[3])], loaded: L[6] === 1};
    }
    last = [L[4], L[5]];
  }
  return {p: last, loaded: false};
}

function hav(a, b) {
  const r = Math.PI / 180, dφ = (b[0] - a[0]) * r, dλ = (b[1] - a[1]) * r;
  const h = Math.sin(dφ / 2) ** 2 + Math.cos(a[0] * r) * Math.cos(b[0] * r) * Math.sin(dλ / 2) ** 2;
  return 2 * 6371 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function frame(t) {
  const traces = [], annotations = [];
  const n = D.runs.length;
  D.runs.forEach((run, k) => {
    const geo = k === 0 ? "geo" : "geo" + (k + 1);
    let km = 0;
    // routes driven so far, one trace per vehicle
    run.vehicles.forEach(v => {
      const lat = [], lon = [];
      for (const L of v.legs) {
        if (t <= L[0]) break;
        const f = Math.min(1, (t - L[0]) / Math.max(L[1] - L[0], 1e-9));
        const end = [L[2] + f * (L[4] - L[2]), L[3] + f * (L[5] - L[3])];
        lat.push(L[2], end[0], null); lon.push(L[3], end[1], null);
        km += hav([L[2], L[3]], end);
      }
      traces.push({type: "scattergeo", geo, mode: "lines", lat, lon, hoverinfo: "skip",
        line: {color: v.color, width: 1.5}, opacity: 0.55, showlegend: false});
    });
    // freights
    const wl = [], wn = [], wc = [], dl = [], dn = [], dc = [], txt = [], dtxt = [];
    let delivered = 0, late = 0, lateH = 0;
    for (const f of run.freights) {
      if (t < f.ready) continue;
      if (f.deliv !== null && t >= f.deliv) {
        dl.push(f.d[0]); dn.push(f.d[1]); dc.push(f.deliv > f.due ? LATE : GOOD);
        dtxt.push(`${f.id}: delivered ${f.deliv > f.due ? "late" : "on time"}`);
        delivered++; if (f.deliv > f.due) { late++; lateH += (f.deliv - f.due) / 3600; }
      } else {
        if (t > f.due) lateH += (t - f.due) / 3600;
        if (f.pick === null || t < f.pick) {
          wl.push(f.p[0]); wn.push(f.p[1]); wc.push(t > f.due ? LATE : WAIT);
          txt.push(`${f.id}: waiting`);
        }
      }
    }
    traces.push({type: "scattergeo", geo, mode: "markers", lat: wl, lon: wn, text: txt, hoverinfo: "text", showlegend: false,
      marker: {symbol: "circle-open", size: 11, color: wc, line: {width: 2.5}}});
    traces.push({type: "scattergeo", geo, mode: "markers", lat: dl, lon: dn, text: dtxt, hoverinfo: "text", showlegend: false,
      marker: {symbol: "square", size: 10, color: dc, line: {color: "#fcfcfb", width: 1.5}}});
    // bases and vehicles
    traces.push({type: "scattergeo", geo, mode: "markers", lat: run.vehicles.map(v => v.base[0]), lon: run.vehicles.map(v => v.base[1]),
      hoverinfo: "skip", showlegend: false,
      marker: {symbol: "diamond-open", size: 12, color: run.vehicles.map(v => v.color), line: {width: 2}}});
    const pos = run.vehicles.map(v => position(v, t));
    traces.push({type: "scattergeo", geo, mode: "markers", lat: pos.map(q => q.p[0]), lon: pos.map(q => q.p[1]),
      text: run.vehicles.map((v, i) => `${v.id}${pos[i].loaded ? " (loaded)" : ""}`), hoverinfo: "text", showlegend: false,
      marker: {size: pos.map(q => q.loaded ? 17 : 11), color: run.vehicles.map(v => v.color), line: {color: "#fcfcfb", width: 2}}});
    const x0 = k / n, x1 = (k + 1) / n;
    annotations.push({text: `<b>${run.title}</b>`, x: (x0 + x1) / 2, y: 1.0, xref: "paper", yref: "paper",
      xanchor: "center", yanchor: "bottom", yshift: 22, showarrow: false, font: {size: 15, color: "#0b0b0b"}});
    annotations.push({text: `${Math.round(km).toLocaleString("en")} km · delivered ${delivered}/${run.freights.length} · ` +
      `<span style="color:${LATE}">${late} late · ${lateH.toFixed(0)} h overdue</span>`,
      x: (x0 + x1) / 2, y: 1.0, xref: "paper", yref: "paper", xanchor: "center", yanchor: "bottom", yshift: 2, showarrow: false,
      font: {size: 13, color: "#52514e"}});
  });
  return {traces, annotations};
}

const geoBase = {
  projection: {type: "mercator"}, resolution: 50, fitbounds: false,
  lataxis: {range: D.lat}, lonaxis: {range: D.lon},
  showland: true, landcolor: "#f3f1ec", showcountries: true, countrycolor: "#b8b2a7",
  showocean: true, oceancolor: "#dde8f0", showlakes: false, showframe: false, bgcolor: "rgba(0,0,0,0)",
};
function layout(annotations) {
  const L = {margin: {l: 8, r: 8, t: 58, b: 8}, paper_bgcolor: "#fcfcfb", annotations, showlegend: false};
  D.runs.forEach((_, k) => {
    const n = D.runs.length, gap = 0.01;
    L[k === 0 ? "geo" : "geo" + (k + 1)] = {...geoBase, domain: {x: [k / n + gap, (k + 1) / n - gap], y: [0, 1]}};
  });
  return L;
}

let t = 0, playing = true, last = null, drawn = null;
const clock = document.getElementById("clock"), slider = document.getElementById("slider");
const HOURS_PER_SECOND = Math.max(2, D.tmax / 3600 / 20);   // whole replay in about 20 s
document.getElementById("speed").textContent = `${HOURS_PER_SECOND.toFixed(0)} h per second`;

window.renderAt = function (ts) {
  t = Math.max(0, Math.min(D.tmax, ts));
  const f = frame(t);
  clock.textContent = hhmm(t);
  slider.value = Math.round(1000 * t / D.tmax);
  const p = drawn ? Plotly.react("map", f.traces, layout(f.annotations)) :
                    Plotly.newPlot("map", f.traces, layout(f.annotations), {displayModeBar: false, responsive: true});
  drawn = true;
  return p;
};

function tick(now) {
  if (playing && last !== null) {
    t += (now - last) / 1000 * HOURS_PER_SECOND * 3600;
    if (t > D.tmax) { t = D.tmax; playing = false; document.getElementById("play").textContent = "Replay"; }
    window.renderAt(t);
  }
  last = now;
  requestAnimationFrame(tick);
}

document.getElementById("play").onclick = () => {
  if (!playing && t >= D.tmax) t = 0;
  playing = !playing;
  document.getElementById("play").textContent = playing ? "Pause" : "Play";
};
slider.oninput = () => { playing = false; document.getElementById("play").textContent = "Play"; window.renderAt(slider.value / 1000 * D.tmax); };

window.renderAt(0).then(() => {
  window.replayReady = true;
  if (!document.body.classList.contains("capture")) requestAnimationFrame(tick);
});
</script>
</body>
</html>
"""
