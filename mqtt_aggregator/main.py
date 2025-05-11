import json, threading, time
from store_service import DailyStore
from mqtt_listener import SuggestionSubscriber
from rest_server import run_rest

with open("config.json") as f:
    config = json.load(f)

store = DailyStore(config["registry_url"])
mqtt_sub = SuggestionSubscriber(config, store)
mqtt_sub.start()

threading.Thread(target=run_rest, args=(store, config["rest_port"]), daemon=True).start()

print("Suggestion-log running... Press CTRL+C to stop.")
try:
    while True:
        time.sleep(60)
except KeyboardInterrupt:
    print("Shutting down.")
