#data_fetcher.py
import time
import requests


def get_catalog(registry_url, retries=10, delay=3):
    for attempt in range(retries):
        try:
            response = requests.get(f"{registry_url}/catalog")
            response.raise_for_status()
            print("Catalog fetched successfully.")
            return response.json()
        except requests.RequestException as e:
            print(f"[Attempt {attempt + 1}] Error fetching catalog: {e}")
            time.sleep(delay)
    print("Failed to fetch catalog after several retries. Exiting.")
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
            print(f"[Attempt {attempt+1}] Fetching {measure} data from: {url} with params: {params}")
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                print(f"Fetched {len(data)} items for {measure}")
                return data
            else:
                print(f"ERROR: adaptor returned {resp.status_code}")
        except Exception as e:
            print(f"ERROR in fetch_data (attempt {attempt+1}): {e}")
        time.sleep(delay)

    print(f"Failed to fetch {measure} after {retries} attempts.")
    return []


def fetch_feedback(adaptor_base, user_id, apartment_id, room_id, duration=168):
    try:
        url = f"{adaptor_base}/getRoomData/{user_id}/{apartment_id}/{room_id}?measurement=feedback&duration={duration}"
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
            print(f"[Feedback] Unexpected status code: {response.status_code}")
    except Exception as e:
        print(f"[Feedback] Error fetching feedback: {e}")
    return {}
