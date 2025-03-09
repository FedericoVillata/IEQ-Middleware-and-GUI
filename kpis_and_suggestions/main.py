from influxdb_client import InfluxDBClient
import pandas as pd
from kpis_classification import *
import json
import requests

# Load configuration from settings file
SETTINGS = "settings.json"
with open(SETTINGS, 'r') as file:
    config = json.load(file)

INFLUX_URL = config["url_db"]
INFLUX_TOKEN = config["influx_token"]
INFLUX_ORG = config["influx_org"]
INFLUX_BUCKET = config["influx_bucket"]

# Function to retrieve data from InfluxDB
def get_data_from_influx():
    client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
    query_api = client.query_api()
    
    query = f'''
    from(bucket: "{INFLUX_BUCKET}")
    |> range(start: -24h)
    |> filter(fn: (r) => r["_measurement"] == "IEQ_Sensors")
    |> filter(fn: (r) => r["_field"] == "CO2" or r["_field"] == "Temperature" or r["_field"] == "Humidity" or r["_field"] == "PM10" or r["_field"] == "TVOC")
    |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
    '''
    
    result = query_api.query_data_frame(org=INFLUX_ORG, query=query)
    client.close()
    return result

# Retrieve data
result = get_data_from_influx()

# Process data if it is not empty
if not result.empty and "_time" in result.columns:
    result["_time"] = pd.to_datetime(result["_time"])
    result["Month"] = result["_time"].dt.month
    result["Season"] = result["Month"].apply(lambda m: "warm" if 5 <= m <= 9 else "cold")

    # Handle missing values
    for col in ["Temperature", "Humidity", "CO2", "PM10", "TVOC"]:
        if col not in result.columns:
            result[col] = -999  # Assign default missing values

    # Apply classification functions
    result["Temperature_Class"] = result.apply(lambda row: classify_temperature(row["Temperature"], row["Season"]), axis=1)
    result["Humidity_Class"] = result["Humidity"].apply(classify_humidity)
    result["CO2_Class"] = result["CO2"].apply(classify_co2)

    # Compute Advanced KPIs
    result["PMV"] = result.apply(lambda row: calculate_pmv(1.2, 0.5, row["Temperature"], row["Temperature"], 0.1, row["Humidity"]), axis=1)
    result["PPD"] = result["PMV"].apply(calculate_ppd)
    result["IEQI"] = result.apply(lambda row: calculate_ieqi(row["CO2"], row["PM10"], row["TVOC"]), axis=1)
    result["ICONE"] = result.apply(lambda row: calculate_icone(row["CO2"], row["TVOC"], row["PM10"], row["Humidity"], row["Temperature"]), axis=1)

    # Classify Advanced KPIs
    result["PMV_Class"] = result["PMV"].apply(classify_pmv)
    result["PPD_Class"] = result["PPD"].apply(classify_ppd)
    result["IEQI_Class"] = result["IEQI"].apply(classify_ieqi)

    # Save the classified data to CSV file
    result.to_csv("classified_kpis.csv", index=False)
    print("Advanced KPIs saved to 'classified_kpis.csv'")
else:
    print("Error: No valid data found.")
