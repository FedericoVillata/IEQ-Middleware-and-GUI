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


def fetch_data(adaptor_base, user_id, apartment_id, measure, start=None, end=None, duration=None, retries=3, delay=2):
    if start and end:
        url = f"{adaptor_base}/getDatainPeriod/{user_id}/{apartment_id}"
        params = {
            "measurement": measure,
            "start": f"{start}T00:00:00Z",
            "stop": f"{end}T23:59:59Z",
        }
    else:
        dur = duration if duration else "168"
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


def fetch_feedback(adaptor_base, user_id, apartment_id, duration=168):
    try:
        url = f"{adaptor_base}/getApartmentData/{user_id}/{apartment_id}?measurement=feedback&duration={duration}"
        response = requests.get(url)
        if response.status_code == 200:
            raw_data = response.json()

            feedback_dict = {}
            for entry in raw_data:
                if "v" in entry and isinstance(entry["v"], str) and ":" in entry["v"]:
                    category, value = entry["v"].split(":", 1)
                    feedback_dict.setdefault(category.strip(), []).append({
                        "type": value.strip(),
                        "time": entry.get("t")
                    })
            return feedback_dict
        else:
            log(f"Unexpected status code: {response.status_code}", level="WARN", context="Feedback")
    except Exception as e:
        log(f"Error fetching feedback: {e}", level="ERROR", context="Feedback")
    return {}