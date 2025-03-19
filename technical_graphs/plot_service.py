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
        /generateCarpetPlot  => restituisce il carpet plot
        /generateLineChart   => restituisce la line chart
        """
        if len(uri) == 1:
            if uri[0] == "generateCarpetPlot":
                return self._generate_carpet()
            elif uri[0] == "generateLineChart":
                return self._generate_line_chart(params)
            elif uri[0] == "getLastWeekRange":
                return self._get_last_week_range()
        raise cherrypy.HTTPError(404, "Endpoint not found.")
    
    def _get_last_week_range(self):
        """
        Legge output.json, calcola la data massima, e restituisce
        start=(max_dt - 7gg) e end=max_dt in formato JSON.
        Esempio di risposta:
        {
          "start": "2025-03-20T00:00:00",
          "end":   "2025-03-27T23:59:59"
        }
        """
        with open("output.json", "r") as f:
            data = json.load(f)

        if not data:
            # Se non ci sono dati, restituiamo un JSON con campi vuoti o simile
            cherrypy.response.status = 200
            return json.dumps({"start": None, "end": None})

        # Converte i timestamp
        dt_objects = []
        for item in data:
            ts = item["timestamp"]
            dt = datetime.fromisoformat(ts.replace("Z", ""))
            dt_objects.append(dt)

        max_dt = max(dt_objects)

        # L'ultima settimana: [start, end]
        start_dt = max_dt - timedelta(days=7)
        # se vuoi includere i dati di quell'ultimo giorno fino a 23:59:59,
        # potresti farlo, ma in genere basta la data di max_dt
        end_dt = max_dt

        # Formattiamo i due datetime in iso con "Z"
        # Esempio: "2025-03-20T00:00:00Z"
        start_str = start_dt.isoformat() + "Z"
        end_str   = end_dt.isoformat() + "Z"

        cherrypy.response.headers['Content-Type'] = "application/json"
        return json.dumps({"start": start_str, "end": end_str})

    def _generate_carpet(self):
        # 1) Leggi i dati da output.json 
        with open("output.json", "r") as f:
            data = json.load(f)

        # Estrai timestamp e temperature
        timestamps = [item["timestamp"] for item in data]
        temps = [item["temperature"] for item in data]

        dt_objects = [
            datetime.fromisoformat(ts.replace("Z", "")) 
            for ts in timestamps
        ]

        # 2) Riorganizza i dati in un dizionario: dict[Giorno] = array di 48 fasce orarie (una ogni 30 min)
        #    Dove l'indice 0..47 corrisponde a (ora * 2 + 0/1 in base ai minuti).
        from collections import defaultdict
        # Avremo day_dict[ 'YYYY-MM-DD' ] = [ nan, nan, ..., 48 volte ... ]
        day_dict = defaultdict(lambda: [np.nan]*48)

        def halfhour_index(dtobj):
            return dtobj.hour*2 + (1 if dtobj.minute>=30 else 0)

        for dt, temp in zip(dt_objects, temps):
            day_str = dt.strftime("%Y-%m-%d")
            hh_idx = halfhour_index(dt)
            day_dict[day_str][hh_idx] = temp

        # 3) Ordina i giorni in ordine cronologico
        all_days = sorted(day_dict.keys())
        n_days = len(all_days)

        # Crea matrice shape = (48, n_days)
        # riga = fascia oraria (0..47)
        # colonna = day index
        matrix = np.zeros((48, n_days))
        for col, day in enumerate(all_days):
            row_values = day_dict[day]  # array di lunghezza 48
            matrix[:, col] = row_values

        # 4) Genera la figura. 
        #    - X => colonna => giorni
        #    - Y => riga => 48 fasce orarie
        fig, ax = plt.subplots(figsize=(12, 6))

        cax = ax.imshow(
            matrix,
            origin='lower',
            aspect='auto',
            cmap='jet',
            vmin=9.5, 
            vmax=31.4
        )

        plt.colorbar(cax, ax=ax, label="Temperature (°C)")

        # Impostiamo i tick dell’asse Y = fasce orarie
        # 0..47 => label ogni ora
        y_ticks = np.arange(0,48,2)  # label ogni ora (2 half-hour = 1h)
        y_labels = [f"{hour:02d}:00" for hour in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # Asse X = giorni
        x_ticks = np.arange(n_days)
        # Metti un tick ogni X giorni, altrimenti se ci sono 300 giorni i tick si sovrappongono
        # Ad esempio uno ogni 10 giorni
        step_x = max(1, n_days//10)
        ax.set_xticks(x_ticks[::step_x])
        ax.set_xticklabels([all_days[i] for i in x_ticks[::step_x]], rotation=45)

        ax.set_xlabel("Date")
        ax.set_ylabel("Time of Day")
        ax.set_title("Temperature Carpet Plot (Days=Columns, Hours=Rows)")

        plt.tight_layout()

        # Salvo in memoria e restituisco
        buffer = BytesIO()
        plt.savefig(buffer, format='png', dpi=100)
        plt.close(fig)

        buffer.seek(0)
        cherrypy.response.headers['Content-Type'] = "image/png"
        return buffer.getvalue()
        pass

    def _generate_line_chart(self, params):
        # 1) Recupera i parametri "start" e "end" se presenti
        start_str = params.get("start", None)
        end_str   = params.get("end", None)

        # 2) Carica i dati da output.json
        with open("output.json", "r") as f:
            data = json.load(f)

        # 3) Estrai e converte i timestamp
        timestamps = [d["timestamp"] for d in data]
        temps = [d["temperature"] for d in data]
        dt_objects = [datetime.fromisoformat(ts.replace("Z","")) for ts in timestamps]

        # 4) Trova la data massima
        if not dt_objects:
            # Se output.json è vuoto, gestisci come vuoi:
            # disegna un grafico vuoto o restituisci un messaggio
            pass
        max_dt = max(dt_objects)

        # 5) Se non ho "start" o "end" => default ultima settimana
        if start_str:
            start_dt = datetime.fromisoformat(start_str.replace("Z",""))
        else:
            # start = max_dt - 7 giorni
            start_dt = max_dt - timedelta(days=7)

        if end_str:
            end_dt = datetime.fromisoformat(end_str.replace("Z",""))
        else:
            # end = max_dt
            end_dt = max_dt

        # 6) Filtra i dati
        filtered_times = []
        filtered_temps = []
        for dt, temp in zip(dt_objects, temps):
            if start_dt <= dt <= end_dt:
                filtered_times.append(dt)
                filtered_temps.append(temp)

        # 7) Crea il grafico a linee (come prima)
        fig, ax = plt.subplots(figsize=(10, 5))
        if filtered_times:
            ax.plot(filtered_times, filtered_temps, marker='o', linewidth=2)
        else:
            ax.text(0.5, 0.5, 'No data in this range', ha='center', va='center', transform=ax.transAxes)

        ax.set_title("Temperature (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel("Temperature (°C)")
        fig.autofmt_xdate()

        buffer = BytesIO()
        plt.savefig(buffer, format='png', dpi=100, bbox_inches='tight')
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
        'server.socket_port': 9092,
        'server.socket_host': '0.0.0.0'
    })
    cherrypy.engine.start()
    cherrypy.engine.block()

if __name__ == "__main__":
    start_service()
