import cherrypy
import json
from matplotlib import dates
import requests
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime
from io import BytesIO, StringIO
import csv
from collections import defaultdict
from matplotlib.colors import TwoSlopeNorm
import calendar

class PlotService:
    """
    Plot service that can generate a carpet or a line chart for any measure:
      /generateCarpetPlot?userId=U&apartmentId=A&measure=M...
      /generateLineChart?userId=U&apartmentId=A&measure=M...
      /exportCsv?userId=U&apartmentId=A&measure=M...
    """

    # Base URL to the adaptor service
    ADAPTOR_BASE = "http://adaptor:8080"
    # Base URL to the registry service (where catalog.json data is exposed)
    REGISTRY_BASE = "http://registry:8081"  # or "http://192.68.0.24:8081" if needed

    @cherrypy.expose
    def generateCarpetPlot(self, **kwargs):
        """
        Example:
          GET /generateCarpetPlot?userId=user0&apartmentId=apartment0&measure=Temperature
              &room=room0&duration=8760&download=png
        Special rules for color scale:
          - Temperature: vmin=-20, vmax=40
            mid-value = "G" from either mechanical_temp_warm or mechanical_temp_cold
            depending on the current season (spring/summer -> warm, autumn/winter -> cold)
          - Humidity: vmin=0, vmax=100
            mid-value = "G" from thresholds.humidity
          - CO2: vmin=400, vmax=12000
            mid-value = "G" from either co2_natural or co2_mechanical
            depending on the "ventilation" field in the apartment’s settings
          - PM10.0: (user-chosen "reasonable" scale)
            For example, vmin=0, vmax=200, mid=50
          - VOC: (user-chosen "reasonable" scale)
            For example, vmin=0, vmax=1000, mid=300
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        measure = kwargs.get("measure", "Temperature")
        room = kwargs.get("room", None)
        duration = kwargs.get("duration", None)
        start = kwargs.get("start", None)
        end = kwargs.get("end", None)
        download = kwargs.get("download", None)

        # 1) Fetch data from the adaptor
        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)
        # Filter by room if provided
        if room:
            data = [d for d in data if d.get("room") == room]
        if not data:
            return self._no_data_image(download=download)

        # 2) Convert times and values into lists
        times, values = [], []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times.append(dt)
            values.append(val)
        if not times:
            return self._no_data_image(download=download)

        # 3) Build a day vs. half-hour matrix
        #    Each day is a column; each half-hour slot is a row
        #    halfHourIndex: integer from 0..47 for each day
        def halfhour_index(dtobj):
            return dtobj.hour * 2 + (1 if dtobj.minute >= 30 else 0)

        # key = 'YYYY-MM-DD', value = [48 half-hour values]
        day_dict = defaultdict(lambda: [np.nan] * 48)
        for dt, val in zip(times, values):
            day_str = dt.strftime("%Y-%m-%d")
            day_dict[day_str][halfhour_index(dt)] = val

        all_days = sorted(day_dict.keys())
        if not all_days:
            return self._no_data_image(download=download)

        n_days = len(all_days)
        matrix = np.zeros((48, n_days), dtype=float)
        for col, day_str in enumerate(all_days):
            matrix[:, col] = day_dict[day_str]

        # 4) Determine color scale extremes and midpoint from the catalog logic
        #    We'll fetch apt settings from the registry and then pick the correct thresholds.
        vmin_val, vmax_val, vcenter_val = self._get_color_scaling(measure, apartmentId)

        # 5) Create the plot
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)

        # Use a TwoSlopeNorm to "center" the colormap around vcenter_val
        norm = TwoSlopeNorm(vcenter=vcenter_val, vmin=vmin_val, vmax=vmax_val)
        cax = ax.imshow(
            matrix,
            origin='lower',
            aspect='auto',
            cmap='jet',
            norm=norm
        )
        plt.colorbar(cax, ax=ax, label=measure)

        # Y-axis: show every hour or half-hour
        # We'll show hour ticks (e.g. 0:00, 1:00, 2:00, ...)
        y_ticks = np.arange(0, 48, 2)   # every 2 half-hours => 1 hour
        y_labels = [f"{h:02d}:00" for h in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # X-axis: day labels
        x_vals = np.arange(n_days)
        step_x = max(1, n_days // 8)  # show ~8 labels across the plot
        ax.set_xticks(x_vals[::step_x])
        ax.set_xticklabels([all_days[i] for i in x_vals[::step_x]], rotation=45)

        ax.set_title(f"{measure} Carpet Plot")
        ax.set_xlabel("Date")
        ax.set_ylabel("Time of Day")

        plt.tight_layout()
        buf = BytesIO()
        plt.savefig(buf, format='png')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="carpet_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def generateLineChart(self, **kwargs):
        """
        GET /generateLineChart?userId=U&apartmentId=A&measure=M&duration=H&room=XYZ&download=png
        If duration>168 => daily average. Then label with date or day.
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

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration_str)
        if room:
            data = [d for d in data if d.get("room") == room]

        if not data:
            return self._no_data_image(download=download)

        times_values = []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times_values.append((dt, val))
        times_values.sort(key=lambda x: x[0])
        if not times_values:
            return self._no_data_image(download=download)

        # If >168 => daily average
        durationH = 168
        if duration_str is not None:
            try:
                durationH = int(duration_str)
            except:
                pass
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

        # Prepare figure
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        x_vals = [tv[0] for tv in times_values]
        y_vals = [tv[1] for tv in times_values]

        ax.plot(x_vals, y_vals, marker='o', linewidth=2, color='blue')
        ax.set_title(f"{measure} (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel(measure)
        plt.grid(True)

        # Format X ticks
        if durationH <= 24:
            # hour only
            ax.xaxis.set_major_formatter(dates.DateFormatter('%H:%M'))
        elif durationH <= 72:
            # date + hour + year
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y %H:%M'))
        else:
            # day + year
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y'))
            ax.xaxis.set_major_locator(dates.DayLocator())

        plt.setp(ax.get_xticklabels(), rotation=45, ha='right')
        plt.tight_layout()

        buf = BytesIO()
        plt.savefig(buf, format='png')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="line_{measure}.png"'
        return buf.getvalue()
    
    @cherrypy.expose
    def exportCsv(self, **kwargs):
        """
        GET /exportCsv?userId=U&apartmentId=A&measure=M&duration=H...
        Writes two columns: "timestamp","measurementValue"
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

        # Build CSV with two columns
        output = StringIO()
        writer = csv.writer(output, delimiter=',', lineterminator='\n')
        writer.writerow(["timestamp", measure])
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            if dt:
                writer.writerow([dt.isoformat(), val])

        return output.getvalue()

    # -----------------------------------------------------
    #               Helper Methods
    # -----------------------------------------------------
    def _fetch_data(self, userId, apartmentId, measure, start, end, duration):
        """
        If start/end are specified => /getDatainPeriod
        else => /getApartmentData
        """
        if start and end:
            url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params = {
                "measurement": measure,
                "start": f"{start}T00:00:00Z",
                "stop":  f"{end}T23:59:59Z",
            }
        else:
            url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            dur = duration if duration else "168"  # default ~1 week
            params = {"measurement": measure, "duration": dur}

        results = []
        try:
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code == 200:
                results = resp.json()
            else:
                print("ERROR: adaptor returned status", resp.status_code)
        except Exception as exc:
            print("ERROR in _fetch_data:", exc)
        return results

    def _parse_time(self, tstring):
        """
        Adaptor can return time in different string formats. Attempt multiple parses.
        """
        fmts = ["%m/%d/%Y, %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"]
        for f in fmts:
            try:
                return datetime.strptime(tstring, f)
            except ValueError:
                pass
        return datetime.now()

    def _no_data_image(self, download=None):
        """
        Return a small placeholder image that says "No Data".
        """
        fig, ax = plt.subplots(figsize=(2, 1), dpi=80)
        ax.text(0.5, 0.5, "No Data", ha="center", va="center", fontsize=12)
        ax.axis("off")
        buf = BytesIO()
        plt.savefig(buf, format='png')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = 'attachment; filename="nodata.png"'
        return buf.getvalue()

    def _get_color_scaling(self, measure, apartmentId):
        """
        Returns (vmin, vmax, vcenter) for the requested measure, reading from the catalog.
        - Temperature => vmin=-20, vmax=40,
            mid = G from mechanical_temp_warm or mechanical_temp_cold based on season
        - Humidity => vmin=0, vmax=100, mid = thresholds.humidity.G
        - CO2 => vmin=400, vmax=12000, mid = thresholds.co2_natural.G or co2_mechanical.G 
            based on "ventilation" in apt settings
        - PM10.0 => user-defined (e.g. vmin=0, vmax=200, mid=50)
        - VOC => user-defined (e.g. vmin=0, vmax=1000, mid=300)
        """

        # Load the relevant apartment's settings from the registry
        apt_settings = self._fetch_apartment_settings(apartmentId)
        thresholds = apt_settings.get("thresholds", {})
        values = apt_settings.get("values", {})

        # Decide measure-based logic
        if measure.lower() == "temperature":
            # extremes
            vmin = -20
            vmax = 40
            # decide warm vs cold season
            if self._is_warm_season():
                mid = thresholds.get("mechanical_temp_warm", {}).get("G", 25)  # fallback if missing
            else:
                mid = thresholds.get("mechanical_temp_cold", {}).get("G", 22)
        elif measure.lower() == "humidity":
            vmin = 0
            vmax = 100
            mid = thresholds.get("humidity", {}).get("G", 60)
        elif measure.lower() == "co2":
            vmin = 400
            vmax = 12000
            ventilation = values.get("ventilation", "nat")  # default if not found
            if ventilation == "mec":
                # co2_mechanical
                mid = thresholds.get("co2_mechanical", {}).get("G", 1200)
            else:
                # co2_natural
                mid = thresholds.get("co2_natural", {}).get("G", 1200)
        elif measure.lower() == "pm10.0":
            # user-chosen example scale
            vmin = 0
            vmax = 200
            mid = 50
        elif measure.lower() == "voc":
            # user-chosen example scale
            vmin = 0
            vmax = 1000
            mid = 300
        else:
            # fallback if measure is not one of the above
            # just pick something safe
            vmin = 0
            vmax = 100
            mid = 50

        return vmin, vmax, mid

    def _fetch_apartment_settings(self, apartmentId):
        """
        Calls the registry to retrieve the 'settings' field for a given apartment.
        """
        try:
            resp = requests.get(f"{self.REGISTRY_BASE}/apartments", timeout=8)
            if resp.status_code == 200:
                apartments = resp.json()  # list of apt
                for apt in apartments:
                    if apt.get("apartmentId") == apartmentId:
                        return apt.get("settings", {})
        except Exception as e:
            print("ERROR fetching apartment settings:", e)

        # fallback if not found or error
        return {}

    def _is_warm_season(self):
        """
        Returns True if current month is in spring/summer,
        otherwise False (autumn/winter).
        For simplicity: months 3..9 => warm, else cold.
        """
        current_month = datetime.now().month
        # March(3) to September(9) => warm
        return 3 <= current_month <= 9


def main():
    cherrypy.config.update({
        "server.socket_host": "0.0.0.0",
        "server.socket_port": 9090
    })

    conf = {
        "/": {
            "tools.sessions.on": True
        }
    }

    cherrypy.tree.mount(PlotService(), "/", conf)
    cherrypy.engine.start()
    cherrypy.engine.block()


if __name__ == "__main__":
    main()
