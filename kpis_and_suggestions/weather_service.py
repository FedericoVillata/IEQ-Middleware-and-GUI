# weather_service.py
import requests
from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")



def get_external_weather(lat, lon):
    try:
        # Validate latitude and longitude ranges
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError(f"Invalid coordinates: lat={lat}, lon={lon}")

        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            f"&hourly=temperature_2m,weather_code"
            f"&timezone=auto&forecast_days=1"
        )

        response = requests.get(url)
        if response.status_code != 200:
            raise Exception(f"Bad response: {response.status_code}")

        data = response.json()
        now_hour = datetime.now().hour
        temp_now = data["hourly"]["temperature_2m"][now_hour]
        code_now = data["hourly"]["weather_code"][now_hour]

        sunny = code_now == 0
        temp_list = data["hourly"]["temperature_2m"][:now_hour + 1]
        temp_drop = len(temp_list) >= 2 and temp_list[-1] < temp_list[0]

        bad_weather_codes = {61, 63, 65, 80, 81, 82}
        bad_days = sum(1 for c in data["hourly"]["weather_code"] if c in bad_weather_codes)

        return {
            "temperature": temp_now,
            "weather_code": code_now,
            "sunny": sunny,
            "temp_drop": temp_drop,
            "bad_days": bad_days
        }

    except Exception as e:
        log(f"Weather fetch failed: {e}", level="ERROR", context="weather_service")
        return {
            "temperature": -999,
            "weather_code": -1,
            "sunny": False,
            "temp_drop": False,
            "bad_days": 0
        }