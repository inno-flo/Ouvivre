"""
Builds dk_meteo_monthly.json: températures et précipitations mensuelles par
kommune sur les 5 dernières années glissantes — l'équivalent danois de
meteo_monthly.json (section « Météo » de l'inspecteur), au même format.

Source : DMI (Danmarks Meteorologiske Institut), Climate Data API, collection
`municipalityValue` — https://opendataapi.dmi.dk/v2/climateData (OGC API
Features, GeoJSON, sans clé, données libres CC BY 4.0 : citer « DMI »).
Documentation : https://www.dmi.dk/friedata/dokumentation/apis/climate-data-api-1

Contrairement à Météo-France, DMI publie directement une valeur par kommune,
calculée sur sa grille climatologique interpolée : ni rattachement aux
postes ni pondération par la population ne sont nécessaires.

Paramètres DMI → clés de meteo_monthly.json :
  - mean_temp            → tm : température moyenne (°C)
  - mean_daily_max_temp  → tx : moyenne des maximales quotidiennes (°C)
  - max_temp_w_date      → xa : maximum absolu du mois (°C)
  - min_temp             → na : minimum absolu du mois (°C)
  - acc_precip           → rr : cumul des précipitations (mm)
  - mean_relative_hum, mean_wind_speed : humidité (%) et vent moyen (m/s),
    pour la température ressentie `tr` (feels_like de build_meteo_data.py).
Le record de chaleur est une valeur de grille : pas de poste, de jour ni de
position (xn, xd, xy, xx absents, tous optionnels côté app).

Fenêtre : de janvier N-5 au mois courant de N, comme pour la France ; DMI
publie le mois courant en cours de mois, marqué `partial`.

Clés : kommunekode à 4 chiffres (« 0101 »), comme dk_kommuner.json (lancer
build_dk_kommuner.py d'abord ; le script vérifie que les 98 kommuner sont
toutes servies).

Run: .venv/bin/python build_dk_meteo_data.py
"""
import json
from datetime import date, datetime, timezone
from pathlib import Path

import requests

from build_meteo_data import feels_like, window

API = "https://opendataapi.dmi.dk/v2/climateData/collections/municipalityValue/items"
OUT = Path(__file__).parent / "data" / "out"
KOMMUNER_PATH = OUT / "dk_kommuner.json"

PAGE_SIZE = 300_000  # maximum accepté par l'API (~7 000 valeurs par paramètre)
PARAMETERS = {
    "mean_temp": "tm",
    "mean_daily_max_temp": "tx",
    "max_temp_w_date": "xa",
    "min_temp": "na",
    "acc_precip": "rr",
    "mean_relative_hum": "um",
    "mean_wind_speed": "ff",
}


def fetch_parameter(parameter_id, start, end):
    """{kommune: {AAAAMM: valeur}} pour un paramètre DMI, toutes pages."""
    params = {
        "timeResolution": "month",
        "parameterId": parameter_id,
        "datetime": f"{start}/{end}",
        "limit": PAGE_SIZE,
        "offset": 0,
    }
    values = {}
    while True:
        r = requests.get(API, params=params, timeout=300)
        r.raise_for_status()
        page = r.json()
        for feature in page["features"]:
            p = feature["properties"]
            month = p["from"][:4] + p["from"][5:7]  # « from » est en heure locale
            values.setdefault(p["municipalityId"], {})[month] = p["value"]
        if page["numberReturned"] < PAGE_SIZE:
            return values
        params["offset"] += PAGE_SIZE


def main():
    today = date.today()
    months = window(today)
    kommuner = {k["code"]: k["nom"] for k in json.loads(KOMMUNER_PATH.read_text(encoding="utf-8"))["kommuner"]}

    # Début la veille de janvier N-5 en UTC : le mois DMI commence à minuit
    # heure locale (UTC+1), soit le 31 décembre à 23 h UTC.
    start = f"{int(months[0][:4]) - 1}-12-31T00:00:00Z"
    end = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    data = {}
    for parameter_id, key in PARAMETERS.items():
        print(f"Downloading {parameter_id} ...")
        data[key] = fetch_parameter(parameter_id, start, end)

    unknown = set().union(*(set(v) for v in data.values())) - set(kommuner)
    assert not unknown, f"kommuner DMI inconnues : {unknown}"

    out = {}
    missing = []
    for code, nom in sorted(kommuner.items()):
        series = {}
        for m in months:
            v = {key: data[key].get(code, {}).get(m) for key in PARAMETERS.values()}
            if v["tm"] is None and v["rr"] is None:
                continue
            entry = {
                "tm": v["tm"],
                "tx": v["tx"],
                "tr": feels_like(v["tm"], v["um"], v["ff"]),
                "rr": v["rr"],
            }
            if v["xa"] is not None:
                entry["xa"] = v["xa"]
            if v["na"] is not None:
                entry["na"] = v["na"]
            if m == months[-1]:
                entry["partial"] = True
            series[m] = entry
        if not series:
            missing.append(code)
            continue
        out[code] = series
        gaps = [m for m in months if m not in series]
        print(f"{code} {nom}: {len(series)} mois" + (f" (manquants : {gaps})" if gaps else ""))

    assert not missing, f"kommuner sans données : {missing}"

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": "DMI — Climate Data API, valeurs mensuelles par kommune (municipalityValue), CC BY 4.0",
        "from": months[0],
        "to": months[-1],
        "kommuner": out,
    }
    (OUT / "dk_meteo_monthly.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(f"Écrit {len(out)} kommuner, {months[0]}–{months[-1]}")


if __name__ == "__main__":
    main()
