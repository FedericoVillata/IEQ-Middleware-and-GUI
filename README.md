# IEQ Middleware and GUI

A full-stack IoT project for **Indoor Environmental Quality (IEQ) monitoring**, data aggregation, KPI analysis, and user-facing visualization.

## Overview

This repository contains an interdisciplinary software system designed to collect environmental data from heterogeneous sources, process it through a middleware layer, compute KPIs and suggestions, and expose the results through a graphical user interface.

The project combines:
- **sensor/data-source integration**
- **middleware and service registry**
- **time-series storage and aggregation**
- **KPI and suggestion generation**
- **Flutter-based GUI/web frontend**
- **Docker-based orchestration**

## Main Components

### Registry
The `registry/` service manages the system catalog and central configuration for devices, services, apartments, and related resources.

### Adaptor
The `adaptor/` module acts as the middleware bridge between incoming device data and the internal storage/services layer.

### MQTT Aggregator
The `mqtt_aggregator/` service subscribes to suggestions/events and exposes them for downstream use through a REST interface.

### KPI and Suggestions Engine
The `kpis_and_suggestions/` module periodically processes apartment-level data, combines internal measurements with external weather information, and generates KPIs and technical/tenant suggestions.

### Device/Data Simulators and Connectors
The repository includes multiple data ingestion sources, such as:
- `pubsimulator/`
- `capetti_devices/`
- `netatmo_devices/`

These modules simulate or acquire environmental measurements from different device ecosystems.

### Visualization and GUI
The project includes:
- a **Flutter application** in `flutter_project/`
- a web deployment folder in `web-release/`
- a plotting service in `technical_graphs/`

Together, these components support dashboarding and user interaction with the IEQ platform.

## Repository Structure

```text
.
├── adaptor/
├── capetti_devices/
├── data/
├── flutter_project/
├── kpis_and_suggestions/
├── letsencrypt/
├── mqtt_aggregator/
├── netatmo_devices/
├── nginx/
├── pubsimulator/
├── registry/
├── technical_graphs/
├── web-release/
├── docker-compose.yml
├── interdisciplinary_report.pdf
└── README.md
```

## Technologies Used

- **Python** for backend services, middleware, KPI processing, and device connectors
- **Flutter / Dart** for the GUI
- **MQTT** for messaging between services
- **InfluxDB** for time-series data storage
- **Docker Compose** for multi-service deployment
- **Nginx Proxy Manager** for web/proxy management

## Key Features

- Multi-service IEQ platform architecture
- Integration of multiple data sources and device ecosystems
- Middleware layer for collection and routing of sensor data
- KPI computation and automated suggestion generation
- REST and MQTT-based communication between modules
- Flutter GUI for end-user interaction
- Containerized deployment with Docker Compose

## Documentation

The repository also includes project documentation and reports, including:
- `interdisciplinary_report.pdf`
- additional user/documentation material in the repository root

## Notes

This repository reflects an interdisciplinary academic/project implementation and contains both backend and frontend components in a single codebase.
