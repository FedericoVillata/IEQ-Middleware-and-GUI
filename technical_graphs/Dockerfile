FROM python:3.9-slim

WORKDIR /app

# Install system libraries needed by matplotlib
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6-dev libpng-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir cherrypy matplotlib numpy requests

# Copy your code into the container
COPY . .

# Start the plot_service
CMD ["python", "plot_service.py"]
