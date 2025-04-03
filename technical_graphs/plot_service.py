import cherrypy
import json
import requests
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime
from io import BytesIO, StringIO
import csv
from collections import defaultdict

class PlotService:
    """
    Plot service that can generate a carpet or a line chart for any measure:
      /generateCarpetPlot?userId=U&apartmentId=A&measure=M...
      /generateLineChart?userId=U&apartmentId=A&measure=M...
      /exportCsv?userId=U&apartmentId=A&measure=M...
    We've shortened the figure size and lowered the DPI
    to produce images faster while retaining decent quality.
    """

    # Base URL to the adaptor service
    ADAPTOR_BASE = "http://adaptor:8080"

    @cherrypy.expose
    def generateCarpetPlot(self, **kwargs):
        """
        Example:
          GET /generateCarpetPlot?userId=user0&apartmentId=apartment0&measure=Temperature
              &room=room0&duration=8760&download=png
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

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        # Filter by room
        if room:
            data = [d for d in data if d.get("room") == room]

        if not data:
            return self._no_data_image(download=download)

        # Convert times and values
        times, values = [], []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times.append(dt)
            values.append(val)
        if not times:
            return self._no_data_image(download=download)

        # Build day x half-hour matrix
        def halfhour_index(dtobj):
            return dtobj.hour * 2 + (1 if dtobj.minute >= 30 else 0)

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

        # Plot
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        # For an example color scale from 10°C to 40°C
        vmin_val = 10
        vmax_val = 40
        cax = ax.imshow(
            matrix,
            origin='lower',
            aspect='auto',
            cmap='jet',
            vmin=vmin_val,
            vmax=vmax_val
        )
        plt.colorbar(cax, ax=ax, label=measure)

        # Y-axis => half-hours
        y_ticks = np.arange(0, 48, 2)
        y_labels = [f"{h:02d}:00" for h in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # X-axis => days
        x_vals = np.arange(n_days)
        step_x = max(1, n_days // 8)
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
        Example:
          GET /generateLineChart?userId=user0&apartmentId=apartment0&measure=Temperature
              &room=room0&duration=8760&download=png
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

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        # Filter room
        if room:
            data = [d for d in data if d.get("room") == room]

        if not data:
            return self._no_data_image(download=download)

        # Convert times and values
        times, values = [], []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times.append(dt)
            values.append(val)
        if not times:
            return self._no_data_image(download=download)

        # Sort by ascending time
        combined = sorted(zip(times, values), key=lambda x: x[0])
        times = [t for (t, _) in combined]
        values = [v for (_, v) in combined]

        # Plot
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        plt.grid()
        ax.plot(times, values, marker='o', linewidth=2)
        ax.set_title(f"{measure} (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel(measure)
        fig.autofmt_xdate()

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
        Example:
          GET /exportCsv?userId=user0&apartmentId=apartment0&measure=Temperature
              &room=room0&duration=8760
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

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        if room:
            data = [d for d in data if d.get("room") == room]

        cherrypy.response.headers["Content-Type"] = "text/csv; charset=utf-8"
        cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="{measure}_data.csv"'

        if not data:
            return "timestamp,value\n"

        output = StringIO()
        writer = csv.writer(output)
        writer.writerow(["timestamp", measure])
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
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
                "measurament": measure,
                "start": f"{start}T00:00:00Z",
                "stop":  f"{end}T23:59:59Z",
            }
        else:
            url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            dur = duration if duration else "168"  # default ~1 week
            params = {"measurament": measure, "duration": dur}

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
        # Common formats from the adaptor
        fmts = ["%m/%d/%Y, %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"]
        for f in fmts:
            try:
                return datetime.strptime(tstring, f)
            except ValueError:
                pass
        return datetime.now()

    def _no_data_image(self, download=None):
        """
        Return a small placeholder image.
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
