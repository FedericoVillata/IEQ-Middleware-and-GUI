import pandas as pd
from kpis_classification import *

# Mock dataset for testing
data = {
    "_time": pd.date_range(start="2024-01-01", periods=5, freq="H"),
    "Temperature": [22, 24, 30, 18, 20],
    "Humidity": [50, 40, 70, 30, 60],
    "CO2": [1000, 1300, 1600, 1100, 900],
    "PM10": [30, 45, 60, 20, 10],
    "TVOC": [0.2, 0.3, 0.5, 0.1, 0.05]
}

# Convert to DataFrame
result = pd.DataFrame(data)

# Add seasonal classification
result["Month"] = result["_time"].dt.month
result["Season"] = result["Month"].apply(lambda m: "warm" if 5 <= m <= 9 else "cold")

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

# Save results for analysis
result.to_csv("mock_test_output.csv", index=False)

print("Mock test data saved to 'mock_test_output.csv'. Check results.")
