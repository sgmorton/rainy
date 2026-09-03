"""
Applet: Rainy?
Summary: Rain intensity ticker
Description: Two 24-hour rain-intensity bars from Open-Meteo hourly precipitation. Houston default.
Author: SamuLab
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL = 300
BAR_X = 8
BAR_W = 48
BAR_H = 6
PX_PER_HOUR = 2
HOURS = 24

# gray -> cyan -> blue -> purple -> red (mm / hour)
INTENSITY = [
    (0.0, "#4B5563"),
    (0.2, "#22D3EE"),
    (1.0, "#3B82F6"),
    (2.5, "#A855F7"),
    (999.0, "#EF4444"),
]

DEFAULT_LOCATION = """{
    "lat": "29.7604",
    "lng": "-95.3698",
    "description": "Houston, TX",
    "locality": "Houston",
    "timezone": "America/Chicago"
}"""

def main(config):
    loc = _location(config)
    hours = _forecast(loc)
    if hours == None:
        return _error("No forecast")

    today, tomorrow = _split_days(hours, loc["timezone"])
    now = time.now().in_location(loc["timezone"])
    now_min = int(now.format("15")) * 60 + int(now.format("04"))

    return render.Root(
        max_age = 600,
        child = render.Box(
            width = 64,
            height = 32,
            color = "#000000",
            child = render.Stack(
                children = [
                    _day_block(0, "TODAY", today, now_min),
                    _day_block(16, "TOM", tomorrow, None),
                ],
            ),
        ),
    )

def _day_block(y0, label, mm, now_min):
    children = [
        render.Padding(
            pad = (1, y0, 0, 0),
            child = render.Text(label, font = "tom-thumb", color = "#9CA3AF"),
        ),
        render.Padding(
            pad = (BAR_X, y0 + 6, 0, 0),
            child = _bar(mm),
        ),
        render.Padding(
            pad = (BAR_X, y0 + 13, 0, 0),
            child = _ticks(),
        ),
    ]
    if now_min != None:
        nx = BAR_X + int(now_min / 60.0 * PX_PER_HOUR)
        if nx < BAR_X:
            nx = BAR_X
        if nx > BAR_X + BAR_W - 1:
            nx = BAR_X + BAR_W - 1
        children.append(
            render.Padding(
                pad = (nx, y0 + 5, 0, 0),
                child = render.Box(width = 1, height = 9, color = "#FFFFFF"),
            ),
        )
    return render.Stack(children = children)

def _bar(mm):
    segs = []
    for i in range(HOURS):
        segs.append(render.Box(width = PX_PER_HOUR, height = BAR_H, color = _color(mm[i])))
    return render.Row(children = segs)

def _ticks():
    # midnight, 6a, 12p, 6p, and right edge
    kids = []
    for h in [0, 6, 12, 18]:
        kids.append(
            render.Padding(
                pad = (h * PX_PER_HOUR, 0, 0, 0),
                child = render.Box(width = 1, height = 1, color = "#4B5563"),
            ),
        )
    kids.append(
        render.Padding(
            pad = (BAR_W - 1, 0, 0, 0),
            child = render.Box(width = 1, height = 1, color = "#4B5563"),
        ),
    )
    return render.Stack(children = kids)

def _color(mm):
    if mm == None or mm < 0:
        return "#23262B"
    last = INTENSITY[0][1]
    for threshold, color in INTENSITY:
        if mm <= threshold:
            return color
        last = color
    return last

def _forecast(loc):
    url = "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&hourly=precipitation&forecast_days=2&timezone=%s" % (
        str(loc["lat"]),
        str(loc["lng"]),
        loc["timezone"],
    )
    res = http.get(url, ttl_seconds = CACHE_TTL)
    if res.status_code != 200 or not res.body():
        return None
    data = res.json()
    if type(data) != "dict":
        return None
    hourly = data.get("hourly")
    if type(hourly) != "dict":
        return None
    times = hourly.get("time")
    precip = hourly.get("precipitation")
    if type(times) != "list" or type(precip) != "list":
        return None
    out = []
    n = len(times)
    if len(precip) < n:
        n = len(precip)
    for i in range(n):
        p = precip[i]
        mm = 0.0
        if type(p) == "int" or type(p) == "float":
            mm = float(p)
        out.append((times[i], mm))
    return out

def _split_days(hours, timezone):
    now = time.now().in_location(timezone)
    today_key = now.format("2006-01-02")
    tomorrow_key = (now + time.parse_duration("24h")).format("2006-01-02")
    today = [-1.0] * HOURS
    next_day = [-1.0] * HOURS
    for stamp, mm in hours:
        if type(stamp) != "string" or len(stamp) < 13:
            continue
        day = stamp[0:10]
        hour = int(stamp[11:13])
        if hour < 0 or hour > 23:
            continue
        if day == today_key:
            today[hour] = mm
        elif day == tomorrow_key:
            next_day[hour] = mm
    return today, next_day

def _location(config):
    lat = 29.7604
    lng = -95.3698
    label = "HOUSTON"
    tz = "America/Chicago"
    raw = config.get("location", DEFAULT_LOCATION)
    if type(raw) == "string" and raw.startswith("{"):
        loc = json.decode(raw)
        if type(loc) == "dict":
            if loc.get("lat"):
                lat = float(str(loc["lat"]))
            if loc.get("lng"):
                lng = float(str(loc["lng"]))
            tz = loc.get("timezone") or tz
            locality = loc.get("locality") or loc.get("description") or "Houston"
            label = locality.split(",")[0].strip().upper()
            if len(label) > 8:
                label = label[:8]
    return {"lat": lat, "lng": lng, "label": label if label else "HOUSTON", "timezone": tz}

def _error(msg):
    return render.Root(
        child = render.Box(
            color = "#000000",
            child = render.Column(
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text("RAINY?", font = "tom-thumb", color = "#22D3EE"),
                    render.Text(msg, font = "tom-thumb", color = "#E5E7EB"),
                ],
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Location",
                desc = "Where to forecast rain. Defaults to Houston.",
                icon = "locationDot",
            ),
        ],
    )
