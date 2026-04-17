---
sidebar_position: 6
---

# Prometheus + Grafana 本地監控 Docker Compose

完整的本地監控 stack，包含 cAdvisor、node-exporter、process-exporter 和 NVIDIA GPU exporter。

## docker-compose.yml

```yaml
version: '3.8'

services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
    volumes:
      - "/:/rootfs:ro"
      - "/var/run:/var/run:ro"
      - "/sys:/sys:ro"
      - "/var/lib/docker:/var/lib/docker:ro"
      - "/dev/disk:/dev/disk:ro"
    ports:
      - "8081:8080"
    networks:
      - monitoring
    command:
      - "--port=8080"
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - "./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro"
      - "./prometheus/prometheus_data:/prometheus/data"
    ports:
      - "9090:9090"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus/data"
    networks:
      - monitoring
    depends_on:
      - cadvisor
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your_password_here  # 記得改掉
    ports:
      - "3001:3000"
    networks:
      - monitoring
    volumes:
      - ./grafana/grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: unless-stopped

  process-exporter:
    image: ncabatoff/process-exporter
    container_name: process-exporter
    ports:
      - "9256:9256"
    volumes:
      - ./process_exporter/config/process-exporter.yml:/config/process-exporter.yml
      - /proc:/host/proc:ro
      - /:/hostfs:ro
    command:
      - "--config.path=/config/process-exporter.yml"
    networks:
      - monitoring
    pid: "host"
    restart: always

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points'
      - '^/(sys|proc|dev|host|etc)($|/)'
    networks:
      - monitoring
    restart: unless-stopped

  nvidia_smi_exporter:
    container_name: nvidia_smi_exporter
    image: utkuozdemir/nvidia_gpu_exporter:1.1.0
    restart: unless-stopped
    devices:
      - /dev/nvidiactl:/dev/nvidiactl
      - /dev/nvidia0:/dev/nvidia0
    volumes:
      - /usr/lib/x86_64-linux-gnu/libnvidia-ml.so:/usr/lib/x86_64-linux-gnu/libnvidia-ml.so
      - /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1:/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
      - /usr/bin/nvidia-smi:/usr/bin/nvidia-smi
    ports:
      - "9835:9835"

networks:
  monitoring:

volumes:
  prometheus_data:
  grafana_data:
```

## 各 Exporter 說明

| Exporter | Port | 用途 |
|----------|------|------|
| cAdvisor | 8081 | Container 層級資源使用（CPU/Memory per container） |
| Prometheus | 9090 | Metrics 收集與查詢 |
| Grafana | 3001 | Dashboard 視覺化 |
| node-exporter | 9100 | 機器層級 metrics（CPU/RAM/Disk/Network） |
| process-exporter | 9256 | Process 層級 metrics |
| nvidia_smi_exporter | 9835 | NVIDIA GPU metrics |
