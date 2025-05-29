#data_fetcher.py
import time
import requests

from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")




def get_catalog(registry_url, retries=10, delay=3):
    for attempt in range(retries):
        try:
            response = requests.get(f"{registry_url}/catalog")
            response.raise_for_status()
            log("Catalog fetched successfully.")
            return response.json()
        except requests.RequestException as e:
            log(f"Error fetching catalog: {e}", level="ERROR", context=f"Attempt {attempt + 1}")
            time.sleep(delay)
    log("Failed to fetch catalog after several retries. Exiting.", level="ERROR")
    exit(1)

#BE CAREFUL, if test=0 duration is in h, if test=1 duration is in m 
def fetch_data(adaptor_base, user_id, apartment_id, measure, start=None, end=None, duration="4", retries=3, delay=2): #change duration as needed
    if start and end:
        url = f"{adaptor_base}/getDatainPeriod/{user_id}/{apartment_id}"
        params = {
            "measurement": measure,
            "start": f"{start}T00:00:00Z",
            "stop": f"{end}T23:59:59Z",
        }
    else:
        dur = duration if duration else "1"
        url = f"{adaptor_base}/getApartmentData/{user_id}/{apartment_id}"
        params = {
            "measurement": measure,
            "duration": dur,
        }

    for attempt in range(retries):
        try:
            log(f"Fetching {measure} data with params: {params}", level="DEBUG", context=f"Attempt {attempt + 1}")
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                if not data:
                    log(f"No {measure} data found (empty list).", level="WARN", context=f"{apartment_id}")
                else:
                    log(f"Fetched {len(data)} items for {measure}", level="INFO")
                return data
            else:
                log(f"Adaptor returned status {resp.status_code} for {measure}", level="ERROR", context=f"{apartment_id}")
        except Exception as e:
            log(f"Exception fetching {measure}: {e}", level="ERROR", context=f"Attempt {attempt + 1}")
        time.sleep(delay)

    log(f"Failed to fetch {measure} after {retries} attempts.", level="ERROR", context=f"{apartment_id}")
    return []


def fetch_feedback(adaptor_base, user_id, apartment_id, duration: int = 168):
    """
    Retrieve the four feedback streams (temperature-, humidity-, environmental-
    satisfaction and service-rating) from the adaptor and return them in
    the format expected by technical_suggestions.py

    Returns
    -------
    dict
        {
          "temperature_perception": [ {"type": 3, "time": "05/23/2025, 10:25:12"}, …],
          "humidity_perception":    [ … ],
          "enviromental_satisfaction": [ … ],   # ← keep the historical typo
          "service_rating":         [ … ]
        }
    """
    category_map = {
        "temperature_perception": "Temperature",
        "humidity_perception":    "Humidity",
        "enviromental_satisfaction": "Environment",  
        "service_rating":         "Service",
    }

    feedback_dict = {}
    for cat_key, measure in category_map.items():
        try:
            url = f"{adaptor_base}/getApartmentData/{user_id}/{apartment_id}"
            params = {"measurement": measure, "duration": duration}
            resp = requests.get(url, params=params, timeout=10)
            resp.raise_for_status()

            # keep only rows coming from the virtual “Feedback” room
            rows = [
                {"type": int(item["v"]), "time": item["t"]}
                for item in resp.json()
                if str(item.get("room", "")).lower() == "feedback"
                   and "v" in item
            ]
            feedback_dict[cat_key] = rows
            log(f"[DEBUG] {cat_key}: {len(rows)} feedbacks fetched", context="fetch_feedback")

        except Exception as e:
            log(f"Error fetching {measure} feedback: {e}", level="ERROR", context="fetch_feedback")
            feedback_dict[cat_key] = []

    return feedback_dict

def fetch_daily_exterior_temps(adaptor_base, user_id, apartment_id, days=7):
    try:
        room_id = "exterior"
        url = f"{adaptor_base}/getDailyAverages/{user_id}/{apartment_id}/{room_id}"
        params = {"measurement": "Temperature", "days": days}
        log(f"Fetching daily exterior temperatures with params: {params}", level="DEBUG", context=f"{apartment_id}")
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        temps = [float(e["v"]) for e in data if "v" in e]
        log(f"Received daily exterior temperatures: {temps}", context=apartment_id)
        return temps
    except Exception as e:
        log(f"Error fetching daily exterior temps: {e}", level="ERROR", context="data_fetcher")
        return []

