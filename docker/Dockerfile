# Dockerfile for migrate-to-db-nf pipeline
# Based on rocker/tidyverse which includes: dplyr, tidyr, readr, glue, rlang, jsonlite

FROM --platform=linux/amd64 rocker/tidyverse:4.4.0

LABEL maintainer="Ryan McKeown"
LABEL description="R environment for Nextflow database migration and QTL analysis pipeline"
LABEL version="1.1.0"

# Install system dependencies for arrow and duckdb
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install additional R packages not in tidyverse base
RUN install2.r --error --skipinstalled \
    yaml \
    optparse \
    arrow \
    duckdb \
    DBI \
    data.table

# Set working directory
WORKDIR /project

# Default command
CMD ["R"]
