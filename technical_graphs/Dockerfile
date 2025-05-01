FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install system dependencies needed by matplotlib
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libfreetype6-dev \
    libpng-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the code
COPY . .

# Expose the port defined in plot_config.json (9090)
EXPOSE 9090

# Start the CherryPy server
CMD ["python", "plot_service.py"]
