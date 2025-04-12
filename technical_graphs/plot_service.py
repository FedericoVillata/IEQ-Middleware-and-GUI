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
    CherryPy service for:
      - Carpet plots (/generateCarpetPlot)
      - Line charts (/generateLineChart)
      - CSV export (/exportCsv)

    Key modification:
      - For CO2, we forcibly set vmin=0, vmax=10000, then read 'G' from the catalog for mid,
        clamping it to [0, 10000].
      - We set colorbar format="%.0f" to avoid scientific notation like 1e4.
    """

    ADAPTOR_BASE = "http://adaptor:8080"
    REGISTRY_BASE = "http://registry:8081"  # Adjust if needed

    @cherrypy.expose
    def generateCarpetPlot(self, **kwargs):
        """
        GET /generateCarpetPlot?userId=U&apartmentId=A&measure=M&duration=H&room=R&download=png

        Produces a day vs. half-hour matrix. 
        For CO2 => forced vmin=0, vmax=10000, mid=G (from the catalog), but clamped.
        We also specify colorbar format="%.0f" to avoid scientific notation.
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

        # 1) Fetch data from adaptor
        data = self._fetch_data(userId, apartmentId, measure, start, end, duration)
        if room:
            data = [d for d in data if d.get("room") == room]
        if not data:
            return self._no_data_image(download)

        # 2) Convert times/values
        times, values = [], []
        for row in data:
            dt = self._parse_time(row["t"])
            val = row["v"]
            times.append(dt)
            values.append(val)
        if not times:
            return self._no_data_image(download)

        # 3) Build day vs. half-hour matrix
        def halfhour_index(dtobj):
            return dtobj.hour * 2 + (1 if dtobj.minute >= 30 else 0)

        day_dict = defaultdict(lambda: [np.nan]*48)
        for dt, val in zip(times, values):
            date_str = dt.strftime("%Y-%m-%d")
            idx = halfhour_index(dt)
            day_dict[date_str][idx] = val

        all_days = sorted(day_dict.keys())
        if not all_days:
            return self._no_data_image(download)

        n_days = len(all_days)
        matrix = np.zeros((48, n_days), dtype=float)
        for col, dStr in enumerate(all_days):
            matrix[:, col] = day_dict[dStr]

        # 4) Get color scale
        vmin_val, vmax_val, vcenter_val = self._get_color_scaling(measure, apartmentId)

        # If the measure is CO2, we forcibly override with [0..10000]
        # and mid from the catalog, but clamp.
        if measure.lower() == "co2":
            # Force vmin=0, vmax=10000
            vmin_val, vmax_val = 0.0, 10000.0
            # If the catalog says G= e.g. 1200 => clamp to [0..10000]
            if vcenter_val < 0:
                vcenter_val = 0
            elif vcenter_val > 10000:
                vcenter_val = 5000  # midpoint of 0..10000

        # If vmin==vmax => offset them to avoid error
        if abs(vmax_val - vmin_val) < 1e-9:
            vmin_val -= 1.0
            vmax_val += 1.0

        # clamp center if needed
        if vcenter_val < vmin_val:
            vcenter_val = (vmin_val + vmax_val)*0.5
        elif vcenter_val > vmax_val:
            vcenter_val = (vmin_val + vmax_val)*0.5

        # TwoSlopeNorm
        norm = TwoSlopeNorm(vcenter=vcenter_val, vmin=vmin_val, vmax=vmax_val)

        # 5) Plot
        fig, ax = plt.subplots(figsize=(12,8), dpi=100)
        cax = ax.imshow(
            matrix,
            origin='lower',
            aspect='auto',
            cmap='jet',
            norm=norm
        )

        # colorbar with no scientific notation => format="%.0f"
        cb = plt.colorbar(cax, ax=ax, label=measure, format="%.0f")

        # Y-axis => hours
        y_ticks = np.arange(0,48,2)
        y_labels = [f"{h:02d}:00" for h in range(24)]
        ax.set_yticks(y_ticks)
        ax.set_yticklabels(y_labels)

        # X-axis => days
        x_vals = np.arange(n_days)
        step_x = max(1,n_days//8)
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
        if download=="png":
            cherrypy.response.headers["Content-Disposition"] = f'attachment; filename="carpet_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def generateLineChart(self, **kwargs):
        """
        GET /generateLineChart?userId=U&apartmentId=A&measure=M&duration=H&room=R&download=png
        If duration>168 => daily average
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        measure = kwargs.get("measure","Temperature")
        room = kwargs.get("room",None)
        duration_str = kwargs.get("duration",None)
        start = kwargs.get("start",None)
        end = kwargs.get("end",None)
        download = kwargs.get("download",None)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration_str)
        if room:
            data = [d for d in data if d.get("room")==room]
        if not data:
            return self._no_data_image(download)

        times_values = []
        for item in data:
            dt = self._parse_time(item["t"])
            val = item["v"]
            times_values.append((dt, val))
        times_values.sort(key=lambda x:x[0])
        if not times_values:
            return self._no_data_image(download)

        durationH=168
        if duration_str is not None:
            try:
                durationH=int(duration_str)
            except:
                pass

        if durationH>168:
            from collections import defaultdict
            day_map=defaultdict(lambda:{"sum":0.0,"count":0})
            for dt,val in times_values:
                dStr=dt.strftime("%Y-%m-%d")
                day_map[dStr]["sum"]+=val
                day_map[dStr]["count"]+=1
            grouped=[]
            for dStr, agg in day_map.items():
                y,m,d=dStr.split("-")
                dt_obj=datetime(int(y),int(m),int(d))
                avg_val=agg["sum"]/agg["count"]
                grouped.append((dt_obj,avg_val))
            grouped.sort(key=lambda x:x[0])
            times_values=grouped

        fig, ax=plt.subplots(figsize=(12,8),dpi=100)
        x_vals=[tv[0] for tv in times_values]
        y_vals=[tv[1] for tv in times_values]

        ax.plot(x_vals,y_vals,marker='o',linewidth=2,color='blue')
        ax.set_title(f"{measure} (Line Chart)")
        ax.set_xlabel("Time")
        ax.set_ylabel(measure)
        plt.grid(True)

        if durationH<=24:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%H:%M'))
        elif durationH<=72:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y %H:%M'))
        else:
            ax.xaxis.set_major_formatter(dates.DateFormatter('%d/%m/%Y'))
            ax.xaxis.set_major_locator(dates.DayLocator())

        plt.setp(ax.get_xticklabels(), rotation=45, ha='right')
        plt.tight_layout()

        buf=BytesIO()
        plt.savefig(buf,format='png')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"]="image/png"
        if download=="png":
            cherrypy.response.headers["Content-Disposition"]=f'attachment; filename="line_{measure}.png"'
        return buf.getvalue()

    @cherrypy.expose
    def exportCsv(self, **kwargs):
        """
        GET /exportCsv?userId=U&apartmentId=A&measure=M&duration=H&room=R
        Writes CSV with columns: timestamp, measureValue
        """
        try:
            userId = kwargs["userId"]
            apartmentId = kwargs["apartmentId"]
        except KeyError:
            raise cherrypy.HTTPError(400, "Missing userId or apartmentId")

        measure = kwargs.get("measure","Temperature")
        room = kwargs.get("room", None)
        duration_str = kwargs.get("duration", None)
        start = kwargs.get("start", None)
        end = kwargs.get("end", None)

        data = self._fetch_data(userId, apartmentId, measure, start, end, duration_str)
        if room:
            data=[d for d in data if d.get("room")==room]

        cherrypy.response.headers["Content-Type"]="text/csv; charset=utf-8"
        cherrypy.response.headers["Content-Disposition"]=f'attachment; filename="{measure}_data.csv"'

        output=StringIO()
        writer=csv.writer(output,delimiter=',',lineterminator='\n')
        writer.writerow(["timestamp", measure])
        for item in data:
            dt=self._parse_time(item["t"])
            val=item["v"]
            if dt:
                writer.writerow([dt.isoformat(), val])
        return output.getvalue()

    # -------------------------------------------------------------------------
    # Helper Methods
    # -------------------------------------------------------------------------
    def _fetch_data(self, userId, apartmentId, measure, start, end, duration):
        """
        If start/end => /getDatainPeriod
        else => /getApartmentData
        """
        if start and end:
            url=f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params={
                "measurement": measure,
                "start": f"{start}T00:00:00Z",
                "stop": f"{end}T23:59:59Z"
            }
        else:
            url=f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            dur=duration if duration else "168"
            params={"measurement": measure, "duration": dur}

        results=[]
        try:
            resp=requests.get(url,params=params,timeout=10)
            if resp.status_code==200:
                results=resp.json()
            else:
                print("ERROR: adaptor returned status", resp.status_code)
        except Exception as e:
            print("ERROR in _fetch_data:", e)
        return results

    def _parse_time(self, tstring):
        """
        The adaptor can return times in multiple formats. We'll try them all.
        """
        fmts=["%m/%d/%Y, %H:%M:%S","%Y-%m-%dT%H:%M:%SZ","%Y-%m-%d %H:%M:%S"]
        for f in fmts:
            try:
                return datetime.strptime(tstring,f)
            except ValueError:
                pass
        return datetime.now()

    def _no_data_image(self, download=None):
        """
        Returns a minimal "No Data" image if there's no data.
        """
        fig, ax=plt.subplots(figsize=(2,1), dpi=80)
        ax.text(0.5,0.5,"No Data",ha="center",va="center",fontsize=12)
        ax.axis("off")
        buf=BytesIO()
        plt.savefig(buf,format='png')
        plt.close(fig)
        buf.seek(0)

        cherrypy.response.headers["Content-Type"]="image/png"
        if download=="png":
            cherrypy.response.headers["Content-Disposition"]='attachment; filename="nodata.png"'
        return buf.getvalue()

    def _get_color_scaling(self, measure, apartmentId):
        """
        Returns (vmin, vmax, mid) from the catalog (but doesn't apply them for CO2 
        because we override with 0..10000 in generateCarpetPlot).
        For others, we parse thresholds to get R and G. 
        """
        apt_settings=self._fetch_apartment_settings(apartmentId)
        thresholds=apt_settings.get("thresholds",{})
        values=apt_settings.get("values",{})

        measure_lower=measure.lower()

        def parse_r(r_val, default_min, default_max):
            if isinstance(r_val,list) and len(r_val)>=2:
                sorted_vals=sorted(float(x) for x in r_val)
                return (sorted_vals[0], sorted_vals[-1])
            elif isinstance(r_val, (int,float)):
                return (float(r_val)-1, float(r_val)+1)
            return (default_min, default_max)

        def parse_g(g_val, fallback):
            if isinstance(g_val,list) and len(g_val)==2:
                return (float(g_val[0])+float(g_val[1]))/2.0
            elif isinstance(g_val, (int,float)):
                return float(g_val)
            return float(fallback)

        # handle "ieqi", "icone", "pmv" if you have them
        if measure_lower=="ieqi":
            ieqi_class=thresholds.get("ieqi_classification",{})
            g_val=ieqi_class.get("G",1.0)
            y_val=ieqi_class.get("Y",2.0)
            r_val=ieqi_class.get("R",4.0)
            vmin, vmax = (float(g_val), float(r_val))
            if vmin>vmax:
                vmin, vmax=vmax,vmin
            mid=float(y_val)
            return (vmin,vmax,mid)

        if measure_lower=="icone":
            icone_class=thresholds.get("icone_classification",{})
            g_val=icone_class.get("G",1.0)
            y_val=icone_class.get("Y",2.0)
            r_val=icone_class.get("R",4.0)
            vmin, vmax=(float(g_val), float(r_val))
            if vmin>vmax:
                vmin,vmax=vmax,vmin
            mid=float(y_val)
            return (vmin,vmax,mid)

        if measure_lower=="pmv":
            pmv_class=thresholds.get("pmv_classification",{})
            pmv_min=pmv_class.get("Very Cold",-2.5)
            pmv_max=pmv_class.get("Very Warm",3.0)
            pmv_mid=pmv_class.get("Neutral",0.5)
            vmin, vmax=(float(pmv_min), float(pmv_max))
            if vmin>vmax:
                vmin, vmax=vmax,vmin
            return (vmin, vmax, float(pmv_mid))

        if measure_lower=="temperature":
            if self._is_warm_season():
                warm_dict=thresholds.get("mechanical_temp_warm",{})
                r_val=warm_dict.get("R",[0.0,40.0])
                g_val=warm_dict.get("G",[22.0,26.0])
            else:
                cold_dict=thresholds.get("mechanical_temp_cold",{})
                r_val=cold_dict.get("R",[0.0,40.0])
                g_val=cold_dict.get("G",[20.0,23.0])
            vmin, vmax=parse_r(r_val,-20.0,40.0)
            mid=parse_g(g_val,24.0)
            return (vmin,vmax,mid)

        if measure_lower=="humidity":
            hum_dict=thresholds.get("humidity",{})
            r_val=hum_dict.get("R",[0,100])
            g_val=hum_dict.get("G",[40,60])
            vmin,vmax=parse_r(r_val,0,100)
            mid=parse_g(g_val,50.0)
            return (vmin,vmax,mid)

        if measure_lower=="co2":
            # We parse, but in generateCarpetPlot we override vmin=0, vmax=10000
            ventilation=values.get("ventilation","nat")
            if ventilation=="mec":
                co2_dict=thresholds.get("co2_mechanical",{})
            else:
                co2_dict=thresholds.get("co2_natural",{})
            r_val=co2_dict.get("R",[400.0,12000.0])
            g_val=co2_dict.get("G",1200.0)
            vmin,vmax=parse_r(r_val,400.0,12000.0)
            mid=parse_g(g_val,1200.0)
            return (vmin,vmax,mid)

        if measure_lower=="pm10.0":
            pm10_dict=thresholds.get("pm10.0",{})
            r_val=pm10_dict.get("R",[0,200])
            g_val=pm10_dict.get("G",50)
            vmin,vmax=parse_r(r_val,0,200)
            mid=parse_g(g_val,50.0)
            return (vmin,vmax,mid)

        if measure_lower=="voc":
            voc_dict=thresholds.get("voc",{})
            r_val=voc_dict.get("R",[0,1000])
            g_val=voc_dict.get("G",300)
            vmin,vmax=parse_r(r_val,0,1000)
            mid=parse_g(g_val,300.0)
            return (vmin,vmax,mid)

        # fallback
        return (0.0,100.0,50.0)

    def _fetch_apartment_settings(self, apartmentId):
        """
        Retrieve apt's settings from registry
        """
        try:
            resp=requests.get(f"{self.REGISTRY_BASE}/apartments",timeout=8)
            if resp.status_code==200:
                arr=resp.json()
                for apt in arr:
                    if apt.get("apartmentId")==apartmentId:
                        return apt.get("settings",{})
        except Exception as e:
            print("Error fetching apt settings:", e)
        return {}

    def _is_warm_season(self):
        """
        Return True for ~Mar-Sep
        """
        m=datetime.now().month
        return 3<=m<=9

def main():
    cherrypy.config.update({
        "server.socket_host":"0.0.0.0",
        "server.socket_port":9090
    })
    conf={
        "/":{
            "tools.sessions.on":True
        }
    }
    cherrypy.tree.mount(PlotService(),"/",conf)
    cherrypy.engine.start()
    cherrypy.engine.block()

if __name__=="__main__":
    main()
