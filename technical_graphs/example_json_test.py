import json
import random
import datetime

def generate_large_output_json(
    start_date="2025-02-12",
    end_date="2026-01-14",
    interval_minutes=30,
    min_temp=9.5,
    max_temp=31.4,
    outfile="output.json"
):
    """
    Genera un dataset finto con dati di temperatura tra min_temp e max_temp,
    a intervalli di 'interval_minutes' minuti, tra le date 'start_date' e 'end_date'.
    Salva i risultati in formato JSON [ {timestamp, temperature}, ... ].
    """

    start_dt = datetime.datetime.fromisoformat(start_date)
    end_dt = datetime.datetime.fromisoformat(end_date)

    delta = datetime.timedelta(minutes=interval_minutes)
    current = start_dt

    data = []

    while current <= end_dt:
        # Temperatura random
        temp = round(random.uniform(min_temp, max_temp), 2)
        item = {
            "timestamp": current.isoformat() + "Z",
            "temperature": temp
        }
        data.append(item)
        current += delta

    with open(outfile, "w") as f:
        json.dump(data, f, indent=2)

    print(f"created {outfile} with {len(data)} measure")


if __name__ == "__main__":
    generate_large_output_json()
