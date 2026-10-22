"""Download free historical Binance USDT-M futures klines (data.binance.vision) for the optimizer."""
import csv, datetime as dt, io, os, urllib.request, zipfile

SYMS = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT", "ADAUSDT", "LINKUSDT", "AVAXUSDT", "SUIUSDT"]
TF = "15m"
MONTHS = 6
BASE = "https://data.binance.vision/data/futures/um"


def get(url):
    try:
        return urllib.request.urlopen(url, timeout=60).read()
    except Exception:
        return None


def rows(blob):
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        for n in z.namelist():
            for line in io.TextIOWrapper(z.open(n)):
                p = line.strip().split(",")
                if len(p) < 6 or not p[0].isdigit():
                    continue
                t = int(p[0])
                if t > 10**14:
                    t //= 1000
                yield (t, p[1], p[2], p[3], p[4], p[5])


os.makedirs("data", exist_ok=True)
today = dt.datetime.utcnow().date()
months = []
y, m = today.year, today.month
for _ in range(MONTHS):
    m -= 1
    if m == 0:
        y, m = y - 1, 12
    months.append((y, m))

for s in SYMS:
    got = {}
    for (yy, mm) in months:
        b = get(f"{BASE}/monthly/klines/{s}/{TF}/{s}-{TF}-{yy}-{mm:02d}.zip")
        if b:
            for r in rows(b):
                got[r[0]] = r
    d = today.replace(day=1)
    while d < today:
        b = get(f"{BASE}/daily/klines/{s}/{TF}/{s}-{TF}-{d.isoformat()}.zip")
        if b:
            for r in rows(b):
                got[r[0]] = r
        d += dt.timedelta(days=1)
    if got:
        with open(f"data/{s}_{TF}.csv", "w", newline="") as f:
            w = csv.writer(f)
            for k in sorted(got):
                w.writerow(got[k])
        print(s, len(got), "bars")
    else:
        print(s, "no data")
