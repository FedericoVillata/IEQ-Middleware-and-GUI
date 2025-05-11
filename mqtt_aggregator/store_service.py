import threading, time, json, os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import requests

class DailyStore:
    """
    Keeps in-memory logs of alerts and suggestions for each apartment,
    and resets them daily at 04:00 local time. ( go to def _schedule_reset(...) to chane reset time)
    Also writes to and loads from a local store.json file.
    """
    def __init__(self, registry_url: str, file_path="store.json"):
        self.data = {}          # {apt: {"tenant": {...}, "technical": [...], "alerts": {...}}}
        self.next_reset = {}    # {apt: datetime in local tz}
        self.registry_url = registry_url
        self.lock = threading.Lock()
        self.file_path = file_path

        self._refresh_apartments()
        self._load_from_json()
        threading.Thread(target=self._reset_watcher, daemon=True).start()

    # ---------- Pubblic APIs ----------

    def add_tenant(self, apt, room, ts, suggestion_id, text):
        with self.lock:
            self._ensure(apt)
            self.data[apt]["tenant"].setdefault(room, []).append(
                {"ts": ts, "id": suggestion_id, "text": text})
            self._write_to_json()

    def add_technical(self, apt, ts, suggestion_id, text):
        with self.lock:
            self._ensure(apt)
            self.data[apt]["technical"].append(
                {"ts": ts, "id": suggestion_id, "text": text})
            self._write_to_json()

    def add_alert(self, apt, room, ts, text):
        with self.lock:
            self._ensure(apt)
            self.data[apt]["alerts"].setdefault(room, []).append(
                {"ts": ts, "text": text})
            self._write_to_json()

    def get_all(self, apt):
        with self.lock:
            return self.data.get(apt, {})

    def get_tenant(self, apt, room=None):
        with self.lock:
            tenant = self.data.get(apt, {}).get("tenant", {})
            return tenant.get(room, []) if room else tenant

    def get_technical(self, apt):
        with self.lock:
            return self.data.get(apt, {}).get("technical", [])

    def get_alerts(self, apt, room=None):
        with self.lock:
            alerts = self.data.get(apt, {}).get("alerts", {})
            return alerts.get(room, []) if room else alerts

    # -------- internal methods (PRIVATE methods) ----------

    def _ensure(self, apt):
        if apt not in self.data:
            self.data[apt] = {"tenant": {}, "technical": [], "alerts": {}}
            self._schedule_reset(apt)

    def _schedule_reset(self, apt, tz_name=None):
        """Calculate next 04:00 local time and save it in self.next_reset."""
        if tz_name is None:
            tz_name = self._apt_tz.get(apt, "UTC")
        now = datetime.now(ZoneInfo(tz_name))
        reset_time = now.replace(hour=4, minute=0, second=0, microsecond=0)   #change parameters to change reset time
        if now >= reset_time:
            reset_time += timedelta(days=1)
        self.next_reset[apt] = reset_time

    def _reset_watcher(self):
        while True:
            with self.lock:
                to_reset = [apt for apt, ts in self.next_reset.items()
                            if datetime.now(ZoneInfo(self._apt_tz.get(apt, "UTC"))) >= ts]
                for apt in to_reset:
                    self.data[apt] = {"tenant": {}, "technical": [], "alerts": {}}
                    self._schedule_reset(apt)
                if to_reset:
                    self._write_to_json()
            time.sleep(60)

    def _refresh_apartments(self, retries=10, delay=3):
        """Try to load apartment → timezone mapping with retries."""
        for attempt in range(1, retries + 1):
            try:
                resp = requests.get(f"{self.registry_url}/apartments", timeout=5)
                resp.raise_for_status()
                apart = resp.json()
                self._apt_tz = {a["apartmentId"]: a.get("timezone", "UTC") for a in apart}
                print(f"[INFO] Loaded apartment timezone mapping (attempt {attempt})")
                return
            except Exception as e:
                print(f"[WARN] Attempt {attempt} failed to fetch registry: {e}")
                time.sleep(delay)

        print("[ERROR] All attempts to reach registry failed. Defaulting to UTC.")
        self._apt_tz = {}


    def _write_to_json(self):
        try:
            with open(self.file_path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=2)
        except Exception as e:
            print("Failed to write to store.json:", e)

    def _load_from_json(self):
        if os.path.exists(self.file_path):
            try:
                with open(self.file_path, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                    if isinstance(raw, dict):
                        self.data = raw
            except Exception as e:
                print("Failed to load from store.json:", e)
