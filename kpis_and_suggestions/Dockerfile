FROM python:3

WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip3 install -r requirements.txt

COPY . .

# Attende che registry:8081 sia pronto, poi esegue main.py
CMD ["./wait-for-it.sh", "registry:8081", "--", "python3", "main.py"]
