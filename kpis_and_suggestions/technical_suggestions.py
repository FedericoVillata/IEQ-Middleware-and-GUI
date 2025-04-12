from datetime import datetime, timedelta

def get_technical_suggestions(classifications, feedback, metrics, settings):
    suggestions = {}

    season = settings["values"].get("season", "cold")
    ventilation = settings["values"].get("ventilation", "nat")

    # Helper: conta reclami per categoria
    def count_complaints(category):
        return len([
            f for f in feedback.get(category, [])
            if f.get("type") == "complaint"
        ])

    # Helper: verifica se i reclami sono recenti (es. ultime 72h)
    def recent_complaints(category, hours=72):
        now = datetime.now()
        recent = [
            f for f in feedback.get(category, [])
            if "time" in f
            and datetime.strptime(f["time"], "%m/%d/%Y, %H:%M:%S") >= now - timedelta(hours=hours)
            and f.get("type") == "complaint"
        ]
        return len(recent)

    # --- COMFORT TERMICO ---

    if count_complaints("thermal_comfort") >= 3 and classifications.get("pmv") in ["Cold", "Hot", "Very Cold", "Very Warm"]:
        suggestions["thermal_review"] = (
            "Numerosi reclami sul comfort termico: verificare sistema di climatizzazione o isolamento."
        )

    if recent_complaints("thermal_comfort") >= 2 and classifications.get("temperature") == "Y":
        suggestions["borderline_temp_review"] = (
            "Reclami recenti e temperatura borderline: considerare miglioramento fine tuning impianti."
        )

    # --- QUALITÀ DELL'ARIA ---

    if count_complaints("co2") >= 2 and metrics.get("co2", 0) > 1200:
        suggestions["ventilation_efficiency"] = (
            "CO₂ elevata e reclami registrati: valutare adeguatezza portata d’aria e strategia di ventilazione."
        )

    if count_complaints("voc") >= 2 and classifications.get("icone") == "R":
        suggestions["pollutant_sources"] = (
            "Sorgenti inquinanti rilevate e feedback ricevuti: verificare materiali, prodotti o fonti interne."
        )

    # --- UMIDITÀ E CONDENSA ---

    if classifications.get("humidity") == "R" and count_complaints("humidity") >= 2:
        suggestions["humidity_control"] = (
            "Umidità fuori range con reclami: valutare installazione di umidificatori o deumidificatori."
        )

    # --- PM10 / PARTICOLATO ---

    if classifications.get("pm10") == "R" and count_complaints("pm10") >= 1:
        suggestions["pm10_action"] = (
            "PM10 critico e segnalazioni utente: considerare filtri o purificatori per migliorare l’aria."
        )

    # --- COMFORT GLOBALE ---

    if classifications.get("overall_score") == "R" and len(feedback.get("general", [])) >= 2:
        suggestions["global_env_review"] = (
            "Comfort generale inadeguato: eseguire audit completo degli ambienti e parametri indoor."
        )

    # --- MANCATA CORRELAZIONE TRA FEEDBACK POSITIVO E KPI ---

    if metrics.get("co2") < 800 and feedback.get("co2", []) and all(f["type"] == "compliment" for f in feedback["co2"]):
        suggestions["co2_optimized"] = "CO₂ costantemente bassa e feedback positivi: strategia di ventilazione efficace."

    # --- EVENTUALE ESTENSIONE ---

    # Potresti aggiungere altre logiche su:
    # - numero di feedback positivi vs negativi
    # - rilevamento mancanza di miglioramento (persistenza KPI critici)
    # - condizioni meteo esterne (se vuoi combinare anche quello)

    return suggestions
