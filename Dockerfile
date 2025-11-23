FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    curl \
    git \
    build-essential \
    libsqlite3-dev \
    zlib1g-dev \
    awscli \
    unzip \
    gdal-bin \
    libgdal-dev \
    python3-gdal \
    && rm -rf /var/lib/apt/lists/*

# Install tippecanoe from source
RUN git clone https://github.com/felt/tippecanoe.git /tmp/tippecanoe && \
    cd /tmp/tippecanoe && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/tippecanoe

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY convert_gdb_in_ecs.py .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Create data directory
RUN mkdir -p /app/data

# Set Python to unbuffered mode for better logging
ENV PYTHONUNBUFFERED=1

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
