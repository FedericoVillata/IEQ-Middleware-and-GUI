# FROM python:3

# WORKDIR /app

# COPY requirements.txt requirements.txt
# RUN pip3 install -r requirements.txt

# COPY . .

# # Attende che registry:8081 sia pronto, poi esegue main.py
# CMD ["./wait-for-it.sh", "registry:8081", "--", "python3", "main.py"]
FROM python:3

WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip3 install -r requirements.txt

COPY . .

# Make wait-for-it.sh executable
RUN chmod +x wait-for-it.sh

# Wait for registry and adaptor to be ready before starting main.py
CMD ["sh", "-c", "./wait-for-it.sh registry:8081 -- ./wait-for-it.sh adaptor:8080 -- python3 main.py"]
