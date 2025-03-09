import json
import pandas as pd
import requests
from kpis_classification import *

# Load configuration from settings file
SETTINGS = "settings.json"
with open(SETTINGS, 'r') as file:
    config = json.load(file)

# Adaptor API endpoint
ADAPTOR_URL = config["adaptor_url"]

# Function to retrieve data from the adaptor

def get_data_from_adaptor(user_id, plant_code, measurement, duration=24):
    """
    Retrieves sensor data from the adaptor API.
    user_id: The user ID
    plant_code: The plant code (apartment ID)
    measurement: The type of measurement (e.g., CO2, Temperature)
    duration: Time duration (default: last 24 hours)
    return: Data in a pandas DataFrame
    """
    url = f"{ADAPTOR_URL}/getData/{user_id}/{plant_code}?measurament={measurement}&duration={duration}"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        df = pd.DataFrame(data)
        if not df.empty:
            df["t"] = pd.to_datetime(df["t"])
        return df
    except requests.exceptions.RequestException as e:
        print(f"Error fetching data: {e}")
        return pd.DataFrame()

# Retrieve and merge data for multiple measurements
measurements = ["CO2", "Temperature", "Humidity", "PM10", "TVOC"]
user_id = "user123"  # Replace with actual user ID
plant_code = "apartment456"  # Replace with actual apartment ID

df_list = []
for measurement in measurements:
    df = get_data_from_adaptor(user_id, plant_code, measurement)
    if not df.empty:
        df.rename(columns={"v": measurement}, inplace=True)
        df_list.append(df)

# Merge dataframes on timestamp
if df_list:
    result = df_list[0]
    for df in df_list[1:]:
        result = pd.merge(result, df, on="t", how="outer")
else:
    print("Error: No valid data found.")
    exit()

# Process data
if not result.empty:
    result["Month"] = result["t"].dt.month
    result["Season"] = result["Month"].apply(lambda m: "warm" if 5 <= m <= 9 else "cold")

    # Handle missing values
    for col in measurements:
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
