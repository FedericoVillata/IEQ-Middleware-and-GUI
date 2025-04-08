# kpis_suggestions.py

SUGGESTION_MAP = {
    "temperature": {
        "R": "Adjust thermostat or increase ventilation.",
        "Very Cold": "Increase heating.",
        "Very Warm": "Use cooling or natural ventilation."
    },
    "humidity": {
        "R": "Use a dehumidifier or humidifier depending on the issue.",
    },
    "co2": {
        "R": "Open windows or check ventilation system.",
        "Extreme": "Urgent: evacuate or ventilate the room immediately."
    },
    "pmv": {
        "Very Cold": "Increase room temperature and consider heavier clothing.",
        "Very Warm": "Decrease room temperature and wear lighter clothing."
    },
    "ppd": {
        "R": "Review thermal comfort parameters (temperature, humidity, clothing)."
    },
    "icone": {
        "R": "Reduce pollution sources or ventilate the space."
    },
    "ieqi": {
        "R": "Review all indoor air quality metrics and act accordingly."
    },
    "Unknown": "Unable to classify. Check sensor data."
}

def get_suggestions(classifications):
    """
    Given a dictionary of metric classifications, return suggestions.
    """
    suggestions = {}
    for metric, label in classifications.items():
        advice = SUGGESTION_MAP.get(metric, {}).get(label)
        if advice:
            suggestions[metric] = advice
    return suggestions
