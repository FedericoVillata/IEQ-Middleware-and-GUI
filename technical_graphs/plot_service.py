import time
import cherrypy
import json
from matplotlib import dates
import requests
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime, timedelta
from io import BytesIO, StringIO
import csv
from collections import defaultdict
from matplotlib.colors import Normalize
import os
from zoneinfo import ZoneInfo
###############
from collections import Counter
###############


CONFIG_PATH = os.path.join(os.path.dirname(__file__), 'plot_config.json')
with open(CONFIG_PATH, 'r') as f:
    config = json.load(f)

ADAPTOR_BASE = config["adaptor_url"]
REGISTRY_BASE = config["registry_url"]
SERVICE_PORT = int(config["port"])

class PlotService:
    """
    PlotService provides two main visualizations:
    1) generateCarpetPlot -> day vs. half-hour carpet plot
    2) generateLineChart -> standard line plot (with daily averages if duration>168)

    Also exportCsv -> returns CSV data of a chosen measure.
    """
    def __init__(self):
        self.ADAPTOR_BASE  = ADAPTOR_BASE
        self.REGISTRY_BASE = REGISTRY_BASE
        self.DEFAULT_TIMEOUT = config.get("request_timeout", 30)
        self.MAX_RETRIES     = config.get("max_retries", 3)

    def _aggregate_every_15min(self, time_value_pairs):
        """
        Return a list of (bucket_start, average_value) tuples,
        grouping raw samples into 15-minute buckets.

        Args:
            time_value_pairs (List[Tuple[datetime, float]]):
                Assumes the list is already sorted by timestamp.

        Returns:
            List[Tuple[datetime, float]]: Aggregated 15-minute series.
        """
        bucket_stats = defaultdict(lambda: {"sum": 0.0, "count": 0})
        for dt, val in time_value_pairs:
            # Floor to the previous 15-minute slot (e.g. 13:07 → 13:00).
            minute_slot = (dt.minute // 15) * 15
            bucket_start = dt.replace(minute=minute_slot,
                                      second=0,
                                      microsecond=0)
            stats = bucket_stats[bucket_start]
            stats["sum"]   += val
            stats["count"] += 1

        aggregated = [
            (t, s["sum"] / s["count"]) for t, s in bucket_stats.items()
        ]
        aggregated.sort(key=lambda x: x[0])
        return aggregated

    ########################################################################################################

    @cherrypy.expose
    @cherrypy.tools.json_out()
    def feedbackHistogram(self, **q):
        """
        Returns a 5‑bucket histogram of feedback ratings (1–5) for the
        requested user / apartment.

        Query parameters
        ----------------
        userId        : str  (required)
        apartmentId   : str  (required)
        field         : str  (optional, default “Temperature”)
        duration      : int  (optional, hours back from now, default 168 h ≈ 1 week)

        Response
        --------
        JSON object like {"1": 12, "2": 33, "3": 57, "4": 18, "5": 4}
        """
        user_id      = q.get("userId")
        apartment_id = q.get("apartmentId")
        field        = q.get("field", "Temperature")
        duration     = int(q.get("duration", 168))

        if not user_id or not apartment_id:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        # Forward the request to the Adaptor, but ask only for the specific
        # measurement and time‑window we need.
        url    = f"{self.ADAPTOR_BASE}/getApartmentData/{user_id}/{apartment_id}"
        params = {"measurement": field, "duration": duration}
        resp   = requests.get(url, params=params, timeout=self.DEFAULT_TIMEOUT)
        resp.raise_for_status()

        # Build the histogram: count values 1‑5 for records tagged as “Feedback”
        counter = Counter()
        for m in resp.json():
            if m.get("room") == "Feedback":
                try:
                    v = int(round(float(m["v"])))
                    if 1 <= v <= 5:
                        counter[v] += 1
                except (ValueError, TypeError):
                    pass

        # Ensure all five buckets are present
        return {str(i): counter.get(i, 0) for i in range(1, 6)}

    ########################################################################################################

    @cherrypy.expose
    def generateCarpetPlot(self, **kwargs):
        """
        GET /generateCarpetPlot?userId=U&apartmentId=A&measure=M&duration=H&room=R&download=png
        
        Builds a day vs. half-hour "carpet" plot for the requested measure over time.
        The color scale is now fixed per measure (no longer centered on the "G" threshold).
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId.")

        measure = kwargs.get("measure", "Temperature")
        room = kwargs.get("room", None)
        duration = kwargs.get("duration", None)
        start = kwargs.get("start", None)
        end = kwargs.get("end", None)
        download = kwargs.get("download", None)

        if duration:
            try:
                duration_hours = int(duration)
                tz_name = "Europe/Rome"            
                try:
                    apt_resp = requests.get(
                        f"{self.REGISTRY_BASE}/apartments/{apartmentId}",
                        timeout=self.DEFAULT_TIMEOUT
                    )
                    if apt_resp.status_code == 200:
                        tz_name = apt_resp.json().get("timezone", tz_name)
                except Exception:
                    pass                                

                now = datetime.now(ZoneInfo(tz_name))

                start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
                elapsed_minutes = int((now - start_of_day).total_seconds() / 60)

                half_hours = elapsed_minutes // 30 
                elapsed_hours = (half_hours * 30) // 60  

                duration_hours += elapsed_hours
                duration = str(duration_hours)
            except Exception as e:
                print(f"Error adjusting duration: {e}")

        # 1) Fetch data from the adaptor
        data = self._fetch_data(userId, apartmentId, measure, start, end, duration, room)
        if room and any("room" in d for d in data):
            data = [d for d in data if d.get("room") == room]
        if not data:
            return self._no_data_image(download)

         # 2) Convert times + values and interpolate small gaps (up to 4 hours)
        time_value_pairs = []
        for row in data:
            dt = self._parse_time(row["t"])
            val = row["v"]
            if isinstance(val, (int, float)):
                time_value_pairs.append((dt, val))

        if not time_value_pairs:
            return self._no_data_image(download)

        time_value_pairs.sort(key=lambda x: x[0])

        interpolated_pairs = []
        for i in range(len(time_value_pairs) - 1):
            current_time, current_val = time_value_pairs[i]
            next_time, next_val = time_value_pairs[i + 1]
            interpolated_pairs.append((current_time, current_val))

            delta = next_time - current_time
            if timedelta(minutes=15) < delta <= timedelta(hours=4):
                steps = int(delta.total_seconds() // (15 * 60))  # 30-minute steps
                for step in range(1, steps):
                    interp_time = current_time + timedelta(minutes=15 * step)
                    interp_val = current_val + (next_val - current_val) * (step / steps)
                    interpolated_pairs.append((interp_time, interp_val))

        interpolated_pairs.append(time_value_pairs[-1])

        # ---------------------------------------------------------------
        # 3) Build a matrix (48 half-hour slots vs. each day)
        # ---------------------------------------------------------------
        def halfhour_index(dtobj):
            return dtobj.hour * 2 + (1 if dtobj.minute >= 30 else 0)

        day_dict = defaultdict(lambda: [np.nan] * 48)
        for dt, val in interpolated_pairs:
            date_str = dt.strftime("%Y-%m-%d")
            idx = halfhour_index(dt)
            day_dict[date_str][idx] = val

        # ----------------------------------------------------------------
        #  FILL MIDNIGHT (slot 0)
        #     • riempi SOLO se esiste prev_sample entro 4 h
        #     • se anche next_sample è entro 4 h ⇒ media
        #     • altrimenti ⇒ valore di prev_sample
        # ----------------------------------------------------------------
        all_days = sorted(day_dict.keys())          # usato anche più avanti
        for day_str in all_days:
            if not np.isnan(day_dict[day_str][0]):
                continue                            # slot già valorizzato

            midnight = datetime.strptime(day_str, "%Y-%m-%d")

            # ultimo campione prima di mezzanotte (se esiste)
            prev_sample = next(
                ((dt, v) for dt, v in reversed(interpolated_pairs) if dt < midnight),
                None
            )
            if not prev_sample:
                continue                            # niente valore prima → lasciamo NaN

            gap_prev = midnight - prev_sample[0]
            if gap_prev > timedelta(hours=4):
                continue                            # troppo lontano → lasciamo NaN

            # primo campione dopo/uguale mezzanotte (se esiste)
            next_sample = next(
                ((dt, v) for dt, v in interpolated_pairs if dt >= midnight),
                None
            )

            if next_sample and (next_sample[0] - prev_sample[0]) <= timedelta(hours=4):
                fill_val = (prev_sample[1] + next_sample[1]) / 2
            else:
                fill_val = prev_sample[1]

            day_dict[day_str][0] = fill_val
        # ----------------------------------------------------------------


        # build the matrix
        n_days = len(all_days)
        matrix = np.zeros((48, n_days), dtype=float)
        for col, dStr in enumerate(all_days):
            matrix[:, col] = day_dict[dStr]


        # 4) Determine color scale
        #    We simply do a linear normalization from a fixed range.
        measure_lc = measure.lower()
        if measure_lc in config["carpet_ranges"]:
            vmin_val, vmax_val = config["carpet_ranges"][measure_lc]
        else:
            # Fallback range
            vmin_val, vmax_val = (0, 100)

        norm = Normalize(vmin=vmin_val, vmax=vmax_val)

        # 5) Plot with matplotlib
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        cax = ax.imshow(
            matrix,
            origin='lower',
            aspect='auto',
            cmap='jet',
            norm=norm
        )

        # Colorbar

        units_map = {
            "temperature": "°C",
            "humidity": "%RH",
            "co2": "ppm",
            "voc": "ppb",
            "pm10.0": "µg/m³",
            "pmv": "arb",
            "ppd": "%",
            "ieqi": "arb",
            "icone": "arb",
            "environment_score": "score",
        }
        unit = units_map.get(measure.lower(), "")

        plt.colorbar(cax, ax=ax, label=f"{measure} ({unit})" if unit else measure, format="%.0f")
        
        # Y-axis => hours
        y_ticks = np.arange(0, 48, 2)
        y_labels = [f"{h:02d}:00" for h in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # X-axis => days
        x_vals = np.arange(n_days)
        # Show ~8 ticks across
        step_x = max(1, n_days // 8)
        ax.set_xticks(x_vals[::step_x])
        ax.set_xticklabels([all_days[i] for i in x_vals[::step_x]], rotation=45)

        ax.set_xlabel("Date")
        ax.set_ylabel("Time of Day")
        ax.set_facecolor('#fdf7ff')

        plt.tight_layout()
        buf = BytesIO()
        plt.savefig(buf, format='png', facecolor='#fdf7ff')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="carpet_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def generateLineChart(self, **kwargs):
        """
        GET /generateLineChart?userId=U&apartmentId=A&measure=M&duration=H&room=R&download=png
        If duration>168 => daily average. (Unmodified logic from previous code.)
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        measure = kwargs.get("measure", "Temperature")
        room = kwargs.get("room", None)
        duration_str = kwargs.get("duration", None)
        start = kwargs.get("start", None)
        end = kwargs.get("end", None)
        download = kwargs.get("download", None)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration_str, room)
        if room and any("room" in d for d in data):
            data = [d for d in data if d.get("room") == room]
        if not data:
            return self._no_data_image(download)

        times_values = []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times_values.append((dt, val))
        times_values.sort(key=lambda x: x[0])
        if not times_values:
            return self._no_data_image(download)

        # If duration>168 => plot daily average
        durationH = 168
        if duration_str is not None:
            try:
                durationH = int(duration_str)
            except:
                pass
        
        if durationH <= 168:
    # 15-minute resolution
            times_values = self._aggregate_every_15min(times_values)

        if durationH > 168:
            from collections import defaultdict
            day_map = defaultdict(lambda: {"sum": 0.0, "count": 0})
            for dt, val in times_values:
                dStr = dt.strftime("%Y-%m-%d")
                day_map[dStr]["sum"] += val
                day_map[dStr]["count"] += 1
            grouped = []
            for dStr, agg in day_map.items():
                y, m, d = dStr.split("-")
                dt_obj = datetime(int(y), int(m), int(d))
                avg_val = agg["sum"] / agg["count"]
                grouped.append((dt_obj, avg_val))
            grouped.sort(key=lambda x: x[0])
            times_values = grouped

        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        x_vals = [tv[0] for tv in times_values]
        y_vals = [tv[1] for tv in times_values]

        ax.plot(x_vals, y_vals, linewidth=2, color='blue')
        ax.set_xlabel("Date")
        units_map = {
            "temperature": "°C",
            "humidity": "%RH",
            "co2": "ppm",
            "voc": "ppb",
            "pm10.0": "µg/m³",
            "pmv": "arb",
            "ppd": "%",
            "ieqi": "arb",
            "icone": "arb",
            "environment_score": "score",
        }
        unit = units_map.get(measure.lower(), "")
        ax.set_ylabel(f"{measure} ({unit})" if unit else measure)
        plt.grid(True)

        # Format x-axis based on duration
        if durationH <= 24:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%H:%M'))
        elif durationH <= 72:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y %H:%M'))
        else:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y'))
            ax.xaxis.set_major_locator(dates.DayLocator())

        plt.setp(ax.get_xticklabels(), rotation=45, ha='right')
        ax.set_facecolor('#fdf7ff')
        plt.tight_layout()

        buf = BytesIO()
        plt.savefig(buf, format='png', facecolor='#fdf7ff')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="line_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def exportCsv(self, **kwargs):
        """
        GET /exportCsv?userId=U&apartmentId=A&measure=M&duration=H&room=R
        Returns a CSV with columns: [timestamp, measureValue].
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        measure = kwargs.get("measure", "Temperature")
        room = kwargs.get("room", None)
        duration_str = kwargs.get("duration", None)
        start = kwargs.get("start", None)
        end = kwargs.get("end", None)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration_str)
        if room:
            data = [d for d in data if d.get("room") == room]

        cherrypy.response.headers["Content-Type"] = "text/csv; charset=utf-8"
        cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="{measure}_data.csv"'

        output = StringIO()
        writer = csv.writer(output, delimiter=';', lineterminator='\n')
        writer.writerow(["timestamp", measure])
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            if dt:
                writer.writerow([dt.isoformat(), val])
        return output.getvalue()

    # ------------------------------------------------
    # Internal Helper Methods
    # ------------------------------------------------
    def _fetch_data(self, userId, apartmentId, measure, start, end, duration, room=None):
        """
        If start/end => /getDatainPeriod
        else => /getApartmentData
        """
        if start and end:
            url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params = {
                "measurement": measure,
                "start": f"{start}T00:00:00Z",
                "stop":  f"{end}T23:59:59Z"
            }
        else:
            if room: 
                url = f"{self.ADAPTOR_BASE}/getRoomData/{userId}/{apartmentId}/{room}"
            else:
                url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            dur = duration if duration else "168"
            params = {"measurement": measure, "duration": dur}

        timeout  = self.DEFAULT_TIMEOUT
        for attempt in range(self.MAX_RETRIES):
            try:
                resp = requests.get(url, params=params, timeout=timeout)
                if resp.status_code == 200:
                    return resp.json()
                print(f"[fetch_data] adaptor status {resp.status_code} – retry {attempt+1}")
            except requests.exceptions.ReadTimeout:
                print(f"[fetch_data] timeout after {timeout}s – retry {attempt+1}")
            except Exception as e:
                print("[fetch_data] other error:", e)
                break          # per ConnectionError, ecc.

            # back-off progressivo
            timeout *= 2
            time.sleep(1)

        return []  

    def _parse_time(self, tstring):
        """
        The adaptor can return times in multiple string formats. We'll try them all.
        """
        fmts = [
            "%m/%d/%Y, %H:%M:%S",
            "%Y-%m-%dT%H:%M:%SZ",
            "%Y-%m-%d %H:%M:%S"
        ]
        for f in fmts:
            try:
                return datetime.strptime(tstring, f)
            except ValueError:
                pass
        return datetime.now()


    def _no_data_image(self, download=None):
        """
        Returns a small placeholder "No Data" image if there are no data points.
        The custom header makes it easy for the Flutter frontend to detect
        the condition and replace the image with a text message instead.
        """
        # <----------- added header
        cherrypy.response.headers["X-No-Data"] = "1"
        # ----------->

        fig, ax = plt.subplots(figsize=(2, 1), dpi=80)
        ax.text(0.5, 0.5, "No Data", ha="center", va="center", fontsize=12)
        ax.axis("off")
        buf = BytesIO()
        plt.savefig(buf, format='png', facecolor='#fdf7ff')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = 'attachment; filename="nodata.png"'
        return buf.getvalue()
    

def CORS():
    cherrypy.response.headers["Access-Control-Allow-Origin"] = "*"
    cherrypy.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    cherrypy.response.headers["Access-Control-Allow-Headers"] = "Content-Type"

    if cherrypy.request.method == "OPTIONS":
            cherrypy.response.status = 200
            cherrypy.response.body = b""
            cherrypy.serving.request.handled = True

def main():
    cherrypy.config.update({
        "server.socket_host": "0.0.0.0",
        "server.socket_port": SERVICE_PORT
    })

    cherrypy.tools.CORS = cherrypy.Tool('before_handler', CORS)
    
    conf = {
        "/": {
            "tools.sessions.on": True,
            "tools.CORS.on": True
        }
    }
    cherrypy.tree.mount(PlotService(), "/", conf)
    cherrypy.engine.start()
    cherrypy.engine.block()


if __name__ == "__main__":
    main()