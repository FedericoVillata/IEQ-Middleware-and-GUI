#!/usr/bin/env python3
# plot_service.py

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

    # --------------------------------------------------------------------------------
    # Adjust this base URL to your actual Adaptor's address:
    # If you're running in Docker with a service name "adaptor", you can do:
    #   ADAPTOR_BASE = "http://adaptor:8080"
    # or if you prefer using the direct IP from docker-compose:
    #   ADAPTOR_BASE = "http://192.68.0.25:8080"
    # Adjust as needed:
    # --------------------------------------------------------------------------------
    ADAPTOR_BASE = "http://adaptor:8080"

    @cherrypy.expose
    def generateCarpetPlot(self, userId="user0", apartmentId="apartment0",
                           measure="Temperature", download=None, room=None,
                           start=None, end=None, duration=None, **kwargs):
        """
        GET /generateCarpetPlot?userId=USER&apartmentId=APT&measure=MEAS&room=ROOM&start=YYYY-MM-DD&end=YYYY-MM-DD&duration=HOURS&download=png
        If 'start' and 'end' are provided, calls /getDatainPeriod on the adaptor.
        Else if 'duration' is provided, calls /getApartmentData with that duration.
        Then filters by 'room' if provided.
        Finally creates a 'carpet plot' of the result with a fixed color scale for temperature.
        """
        print("DEBUG: generateCarpetPlot =>", userId, apartmentId, measure, room, start, end, duration, download)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        # Filter by room if requested
        if room:
            before_len = len(data)
            data = [d for d in data if d.get("room") == room]
            print(f"DEBUG: after room filter => {len(data)}/{before_len}")

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

        # Build a day x half-hour matrix for the carpet plot
        def halfhour_index(dtobj):
            return dtobj.hour * 2 + (1 if dtobj.minute >= 30 else 0)

        day_dict = defaultdict(lambda: [np.nan] * 48)
        for dt, val in zip(times, values):
            day_str = dt.strftime("%Y-%m-%d")
            idx = halfhour_index(dt)
            day_dict[day_str][idx] = val

        all_days = sorted(day_dict.keys())
        if not all_days:
            return self._no_data_image(download=download)

        n_days = len(all_days)
        matrix = np.zeros((48, n_days), dtype=float)
        for col, day_str in enumerate(all_days):
            matrix[:, col] = day_dict[day_str]

        # Plot
        fig, ax = plt.subplots(figsize=(12, 6))

        # For temperature example: 10 => 40 so 20C is greenish in 'jet' colormap
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
        plt.colorbar(cax, ax=ax, label=f"{measure}")

        # Y-axis => half-hours
        y_ticks = np.arange(0, 48, 2)
        y_labels = [f"{h:02d}:00" for h in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # X-axis => days
        x_ticks = np.arange(n_days)
        step_x = max(1, n_days // 10)
        ax.set_xticks(x_ticks[::step_x])
        ax.set_xticklabels([all_days[i] for i in x_ticks[::step_x]], rotation=45)

        ax.set_xlabel("Date")
        ax.set_ylabel("Time of Day")
        ax.set_title(f"{measure} Carpet Plot")

        plt.tight_layout()
        buf = BytesIO()
        plt.savefig(buf, format='png', dpi=100)
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="carpet_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def generateLineChart(self, userId="user0", apartmentId="apartment0",
                          measure="Temperature", download=None, room=None,
                          start=None, end=None, duration=None, **kwargs):
        """
        GET /generateLineChart?userId=USER&apartmentId=APT&measure=MEAS&room=ROOM&start=YYYY-MM-DD&end=YYYY-MM-DD&duration=HOURS&download=png
        Similar to generateCarpetPlot but produces a line chart.
        """
        print("DEBUG: generateLineChart =>", userId, apartmentId, measure, room, start, end, duration, download)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        # Filter by room if requested
        if room:
            before_len = len(data)
            data = [d for d in data if d.get("room") == room]
            print(f"DEBUG: after room filter => {len(data)}/{before_len}")

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

        # Sort by date
        combined = sorted(zip(times, values), key=lambda x: x[0])
        times = [pair[0] for pair in combined]
        values = [pair[1] for pair in combined]

        fig, ax = plt.subplots(figsize=(10, 5))
        ax.plot(times, values, marker='o', linewidth=2)
        ax.set_title(f"{measure} (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel(measure)
        fig.autofmt_xdate()

        plt.tight_layout()
        buf = BytesIO()
        plt.savefig(buf, format='png', dpi=100)
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="line_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def exportCsv(self, userId="user0", apartmentId="apartment0",
                  measure="Temperature", room=None, start=None, end=None, duration=None, **kwargs):
        """
        GET /exportCsv?userId=USER&apartmentId=APT&measure=MEAS&room=ROOM&start=YYYY-MM-DD&end=YYYY-MM-DD&duration=HOURS
        Exports the data in CSV format (timestamp, value).
        """
        print("DEBUG: exportCsv =>", userId, apartmentId, measure, room, start, end, duration)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)

        # Filter by room if requested
        if room:
            before_len = len(data)
            data = [d for d in data if d.get("room") == room]
            print(f"DEBUG: after room filter => {len(data)}/{before_len}")

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

    # ----------------------------- HELPER METHODS ------------------------------
    def _fetch_data(self, userId, apartmentId, measure, start, end, duration):
        """
        If 'start' and 'end' are provided => calls /getDatainPeriod
        else if 'duration' => calls /getApartmentData
        else => defaults to 168 hours
        """
        if start and end:
            # date range approach
            adaptor_url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params = {
                "measurament": measure,
                "start": f"{start}T00:00:00Z",
                "stop":  f"{end}T23:59:59Z",
            }
            print("DEBUG: calling getDatainPeriod =>", adaptor_url, params)
        else:
            # fallback to duration approach
            dur = duration if duration else "168"
            adaptor_url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            params = {
                "measurament": measure,
                "duration": dur,
            }
            print("DEBUG: calling getApartmentData =>", adaptor_url, params)

        results = []
        try:
            resp = requests.get(adaptor_url, params=params, timeout=10)
            print("DEBUG: adaptor response =>", resp.status_code)
            if resp.status_code == 200:
                results = resp.json()
                print("DEBUG: parsed JSON =>", len(results), "records")
            else:
                print("ERROR: adaptor returned status", resp.status_code)
        except Exception as exc:
            print("ERROR in _fetch_data:", exc)
        return results

    def _parse_time(self, timestr):
        """
        Attempt to parse time from the adaptor's JSON. 
        The adaptor often returns "MM/DD/YYYY, HH:MM:SS" or ISO8601.
        """
        fmts = ["%m/%d/%Y, %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"]
        for f in fmts:
            try:
                return datetime.strptime(timestr, f)
            except ValueError:
                pass
        # fallback
        return datetime.now()

    def _no_data_image(self, download=None):
        """
        Return a small placeholder image if no data is available.
        """
        fig, ax = plt.subplots(figsize=(2, 1))
        ax.text(0.5, 0.5, "No Data", ha="center", va="center")
        ax.axis("off")

        buf = BytesIO()
        plt.savefig(buf, format="png", dpi=50)
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        if download == "png":
            cherrypy.response.headers["Content-Disposition"] = 'attachment; filename="nodata.png"'
        return buf.getvalue()

def main():
    cherrypy.config.update({
        'server.socket_host': '0.0.0.0',
        'server.socket_port': 9090
    })

    conf = {
        '/': {
            'tools.sessions.on': True
        }
    }

    cherrypy.tree.mount(PlotService(), '/', conf)
    cherrypy.engine.start()
    cherrypy.engine.block()

if __name__ == '__main__':
    main()
