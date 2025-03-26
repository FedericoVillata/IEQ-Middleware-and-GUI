import cherrypy
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime, timedelta
from io import BytesIO

class ChartService(object):
    exposed = True

    def GET(self, *uri, **params):
        """
        Endpoints:
          /generateCarpetPlot  => returns carpet plot PNG
          /generateLineChart   => returns line chart PNG
          /getLastWeekRange    => returns default last-week range
          /exportCsv           => returns CSV for the given range & metric
        """
        if len(uri) == 1:
            if uri[0] == "generateCarpetPlot":
                return self._generate_carpet(params)
            elif uri[0] == "generateLineChart":
                return self._generate_line_chart(params)
            elif uri[0] == "getLastWeekRange":
                return self._get_last_week_range()
            elif uri[0] == "exportCsv":
                return self._export_csv(params)
        raise cherrypy.HTTPError(404, "Endpoint not found.")

    # ----------------------------------------------------------------------
    # 1) Return the last-week range from output.json
    # ----------------------------------------------------------------------
    def _get_last_week_range(self):
        with open("output.json", "r") as f:
            data = json.load(f)

        if not data:
            cherrypy.response.status = 200
            return json.dumps({"start": None, "end": None})

        dt_objects = []
        for item in data:
            ts = item["timestamp"]
            dt = datetime.fromisoformat(ts.replace("Z", ""))
            dt_objects.append(dt)

        max_dt = max(dt_objects)
        start_dt = max_dt - timedelta(days=7)
        end_dt = max_dt

        start_str = start_dt.isoformat() + "Z"
        end_str   = end_dt.isoformat() + "Z"

        cherrypy.response.headers['Content-Type'] = "application/json"
        return json.dumps({"start": start_str, "end": end_str})

    # ----------------------------------------------------------------------
    # 2) Generate carpet plot, now with optional [start, end, metric]
    # ----------------------------------------------------------------------
    def _generate_carpet(self, params):
        """
        Carpet plot con:
        - Asse X = giorni (0..N-1), da sinistra a destra,
        - Asse Y = 48 fasce orarie (0..47), dal basso verso l’alto.
        - Le date (tipo "12 Feb", "26 Mar", ecc.) verranno mostrate in basso sull'asse X
        e l’ora del giorno (00:00 .. 23:30) sull’asse Y.

        Se vuoi opzionalmente filtrare start/end (da query string),
        scommenta il blocco di codice dedicato.
        """
        import json
        import numpy as np
        import matplotlib.pyplot as plt
        from datetime import datetime, timedelta
        from io import BytesIO
        import cherrypy

        # 1) Legge i dati da output.json
        with open("output.json", "r") as f:
            data = json.load(f)

        # Estrai timestamp e temperature
        timestamps = [item["timestamp"] for item in data]
        temps = [item["temperature"] for item in data]
        dt_objects = [
            datetime.fromisoformat(ts.replace("Z", ""))
            for ts in timestamps
        ]

        if not dt_objects:
            return self._empty_png("No data in file")

        # -- Se desideri filtrare date, scommenta e gestisci parametri 'start' e 'end' --
        start_str = params.get("start")
        end_str   = params.get("end")
        max_dt = max(dt_objects)

        if start_str:
            start_dt = datetime.fromisoformat(start_str.replace("Z",""))
        else:
            start_dt = max_dt - timedelta(days=7)  # default ultima settimana

        if end_str:
            end_dt = datetime.fromisoformat(end_str.replace("Z",""))
        else:
            end_dt = max_dt

        # Filtra i dati per stare nel range [start_dt, end_dt]
        filtered_dt = []
        filtered_temp = []
        for dt, temp in zip(dt_objects, temps):
            if start_dt <= dt <= end_dt:
                filtered_dt.append(dt)
                filtered_temp.append(temp)

        if not filtered_dt:
            return self._empty_png("No data in selected range")

        # 2) Riorganizza in day_dict[YYYY-MM-DD] = array(48) di temperature
        from collections import defaultdict
        day_dict = defaultdict(lambda: [np.nan]*48)

        def halfhour_index(dtobj):
            # converte ora+minuto in indice 0..47
            return dtobj.hour*2 + (1 if dtobj.minute >= 30 else 0)

        for dt, temp in zip(filtered_dt, filtered_temp):
            day_str = dt.strftime("%Y-%m-%d")
            hh_idx = halfhour_index(dt)
            day_dict[day_str][hh_idx] = temp

        # 3) Ordina i giorni cronologicamente e crea la matrice shape = (48, n_days)
        #    => righe=48 fasce orarie, colonne=n_days
        all_days = sorted(day_dict.keys())
        n_days = len(all_days)

        matrix = np.zeros((48, n_days))
        for col, day in enumerate(all_days):
            row_values = day_dict[day]  # array di 48
            matrix[:, col] = row_values

        # 4) Genera la figura: 
        #    - X => colonna => day index
        #    - Y => riga => half-hour slot (0..47)
        fig, ax = plt.subplots(figsize=(12, 6))

        cax = ax.imshow(
            matrix,
            origin='lower',  # 0..47 dal basso in alto
            aspect='auto',
            cmap='jet',
            vmin=9.5,
            vmax=31.4
        )

        plt.colorbar(cax, ax=ax, label="Temperature (°C)")

        # Impostiamo i tick dell'asse X = giorni
        x_ticks = np.arange(n_days)
        # Se n_days è grande, mostriamo un tick ogni step_x
        step_x = max(1, n_days // 10)
        ax.set_xticks(x_ticks[::step_x])
        # Label => "12 Feb", "26 Mar", ecc. 
        # Esempio: prendi i primi 10 caratteri di day per ridurre sovrapposizioni
        # Oppure converti la stringa in datetime e formatti come vuoi
        x_labels = []
        for i in x_ticks[::step_x]:
            day_str = all_days[i]
            dt_day = datetime.strptime(day_str, "%Y-%m-%d")
            # Formato tipo "12 Feb"
            day_label = dt_day.strftime("%d %b")
            x_labels.append(day_label)

        ax.set_xticklabels(x_labels, rotation=45)

        # Asse Y = 48 fasce orarie 
        # label ogni ora => y= 0..47 => label su 0, 2, 4, ...
        y_ticks = np.arange(0, 48, 2)
        y_labels = [f"{hour:02d}:00" for hour in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        ax.set_xlabel("Date (sorted from earliest to latest)")
        ax.set_ylabel("Hour of Day (in 30-min increments)")
        ax.set_title("Temperature Carpet Plot (X=Days, Y=Hours)")

        plt.tight_layout()

        # 5) Salvo in memoria e restituisco
        buf = BytesIO()
        plt.savefig(buf, format='png', dpi=100)
        plt.close(fig)
        buf.seek(0)
        cherrypy.response.headers['Content-Type'] = "image/png"
        return buf.getvalue()



    # ----------------------------------------------------------------------
    # 3) Generate line chart, with optional [start, end, metric]
    # ----------------------------------------------------------------------
    def _generate_line_chart(self, params):
        start_str = params.get("start", None)
        end_str   = params.get("end", None)
        metric    = params.get("metric", "Temperature")

        # Decide which field is relevant
        field_name = "temperature"
        if metric.lower() == "humidity":
            field_name = "humidity"
        elif metric.lower() == "co2":
            field_name = "co2"
        elif metric.lower() == "pm10":
            field_name = "pm10"
        elif metric.lower() == "tvoc":
            field_name = "tvoc"

        with open("output.json", "r") as f:
            data = json.load(f)

        timestamps = []
        values = []
        for item in data:
            if field_name not in item:
                continue
            ts = item["timestamp"]
            val = item[field_name]
            timestamps.append(ts)
            values.append(val)

        dt_objects = [datetime.fromisoformat(ts.replace("Z","")) for ts in timestamps]
        if not dt_objects:
            return self._empty_png("No data found in the file")

        max_dt = max(dt_objects)
        if start_str:
            start_dt = datetime.fromisoformat(start_str.replace("Z",""))
        else:
            start_dt = max_dt - timedelta(days=7)
        if end_str:
            end_dt = datetime.fromisoformat(end_str.replace("Z",""))
        else:
            end_dt = max_dt

        filtered_times = []
        filtered_vals  = []
        for dt, v in zip(dt_objects, values):
            if start_dt <= dt <= end_dt:
                filtered_times.append(dt)
                filtered_vals.append(v)

        fig, ax = plt.subplots(figsize=(10, 5))
        if filtered_times:
            ax.plot(filtered_times, filtered_vals, marker='o', linewidth=2)
        else:
            ax.text(0.5, 0.5, 'No data in this range',
                    ha='center', va='center', transform=ax.transAxes)

        ax.set_title(f"{metric} (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel(f"{metric} (?)")
        fig.autofmt_xdate()

        buffer = BytesIO()
        plt.savefig(buffer, format='png', dpi=100, bbox_inches='tight')
        plt.close(fig)
        buffer.seek(0)

        cherrypy.response.headers["Content-Type"] = "image/png"
        return buffer.getvalue()

    # ----------------------------------------------------------------------
    # 4) Export CSV with [start, end, metric]
    # ----------------------------------------------------------------------
    def _export_csv(self, params):
        start_str = params.get("start", None)
        end_str   = params.get("end", None)
        metric    = params.get("metric", "Temperature")

        field_name = "temperature"
        if metric.lower() == "humidity":
            field_name = "humidity"
        elif metric.lower() == "co2":
            field_name = "co2"
        elif metric.lower() == "pm10":
            field_name = "pm10"
        elif metric.lower() == "tvoc":
            field_name = "tvoc"

        with open("output.json", "r") as f:
            data = json.load(f)

        # parse times
        rows = []
        dt_list = []
        for item in data:
            if field_name not in item:
                continue
            ts = item["timestamp"]
            val = item[field_name]
            dt = datetime.fromisoformat(ts.replace("Z",""))
            dt_list.append((dt, val))

        if not dt_list:
            cherrypy.response.headers['Content-Type'] = "text/csv"
            return "timestamp,value\n"

        max_dt = max([x[0] for x in dt_list])
        if start_str:
            start_dt = datetime.fromisoformat(start_str.replace("Z",""))
        else:
            start_dt = max_dt - timedelta(days=7)
        if end_str:
            end_dt = datetime.fromisoformat(end_str.replace("Z",""))
        else:
            end_dt = max_dt

        # filter
        filtered = [(d, v) for (d, v) in dt_list if start_dt <= d <= end_dt]

        # build CSV
        csv_lines = ["timestamp,value"]
        for d, v in sorted(filtered, key=lambda x: x[0]):
            dstr = d.isoformat() + "Z"
            csv_lines.append(f"{dstr},{v}")

        csv_text = "\n".join(csv_lines)
        cherrypy.response.headers['Content-Type'] = "text/csv"
        return csv_text

    # ----------------------------------------------------------------------
    # Helper function to return a small "No data" PNG
    # ----------------------------------------------------------------------
    def _empty_png(self, text):
        fig, ax = plt.subplots(figsize=(4,2))
        ax.text(0.5, 0.5, text, ha='center', va='center', transform=ax.transAxes)
        ax.set_xticks([])
        ax.set_yticks([])
        buffer = BytesIO()
        plt.savefig(buffer, format='png')
        plt.close(fig)
        buffer.seek(0)
        cherrypy.response.headers["Content-Type"] = "image/png"
        return buffer.getvalue()


def start_service():
    conf = {
        '/': {
            'request.dispatch': cherrypy.dispatch.MethodDispatcher(),
        }
    }
    cherrypy.tree.mount(ChartService(), '/', conf)
    cherrypy.config.update({
        'server.socket_port': 9090,
        'server.socket_host': '0.0.0.0'
    })
    cherrypy.engine.start()
    cherrypy.engine.block()

if __name__ == "__main__":
    start_service()
