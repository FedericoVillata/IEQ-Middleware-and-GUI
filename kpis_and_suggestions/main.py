from influxdb_client import InfluxDBClient
import pandas as pd
from kpis_classification import *

# Database connection configuration
INFLUX_URL = "http://localhost:8086"
INFLUX_TOKEN = "your_token"
INFLUX_ORG = "your_organization"
INFLUX_BUCKET = "your_bucket"

# Create the InfluxDB client
client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)

# Query to retrieve data from the last 24 hours
query = f'''
from(bucket: "{INFLUX_BUCKET}")
|> range(start: -24h)
|> filter(fn: (r) => r["_measurement"] == "IEQ_Sensors")
|> filter(fn: (r) => r["_field"] == "CO2" or r["_field"] == "Temperature" or r["_field"] == "Humidity" or r["_field"] == "PM10" or r["_field"] == "TVOC")
|> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
'''

# Execute the query and store the results in a Pandas DataFrame
query_api = client.query_api()
result = query_api.query_data_frame(org=INFLUX_ORG, query=query)

# Close the database connection
client.close()

# Process data
if "_time" in result.columns:
    result["_time"] = pd.to_datetime(result["_time"])
    result["Month"] = result["_time"].dt.month
    result["Season"] = result["Month"].apply(lambda m: "warm" if 5 <= m <= 9 else "cold")

    # Handle missing values
    for col in ["Temperature", "Humidity", "CO2", "PM10", "TVOC"]:
        if col not in result.columns:
            result[col] = -999  # Default missing values

    # Apply classification functions
    result["Temperature_Class"] = result["Temperature"].apply(lambda x: classify_temperature(x, result["Season"].mode()[0]))
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

    # Save the classified data
    result.to_csv("classified_kpis.csv", index=False)
    print("Advanced KPIs saved to 'classified_kpis.csv'")

else:
    print("Error: No valid data found.")
