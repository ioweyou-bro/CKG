# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clinical Knowledge Graph (CKG) is a Python-based platform for analyzing proteomics and clinical data, integrating knowledge from multiple biomedical databases. The system uses Neo4j graph database (v4.2.3) to represent 16+ million nodes and 220+ million relationships across ontologies, databases, and experimental data.

**Important**: CKG has been integrated into the BioCypher framework. See https://doi.org/10.1038/s41587-023-01848-y

## Technology Stack

- **Python**: 3.10 (originally 3.7.9, upgraded to 3.10)
- **Graph Database**: Neo4j 4.2.3 with Graph Data Science library (1.5.1) and APOC (4.2.0.4)
- **Web Framework**: Flask 2.3.3 + Dash 2.14.1 for interactive reports
- **Task Queue**: Celery 5.3.4 + Redis for background processing
- **R**: Version 3.6.1 (for statistical analyses via rpy2)
- **Node.js**: 18 LTS (for JupyterHub configurable-http-proxy)

## Core Commands

### Initial Setup
```bash
# Install dependencies
pip install -r requirements.txt

# Initialize CKG (creates directory structure and config files)
python3 ckg/init.py
# OR
python3 -m ckg init
```

### Database Building

```bash
# Full database build (imports all ontologies, databases, experiments)
ckg_build -u <username> -b full -n 4

# Minimal update (after restoring from dump, updates licensed DBs only)
ckg_build -u <username> -b minimal -n 3

# Import specific data types
ckg_build -u <username> -b import -i databases ontologies -d UniProt STRING

# Load specific entities into Neo4j
ckg_build -u <username> -b load -l ontologies proteins

# Update text mining only
ckg_update_textmining
```

### Running the Application

```bash
# Production mode (via uWSGI + nginx)
uwsgi --ini /etc/uwsgi/apps-enabled/uwsgi.ini

# Development mode
ckg_app  # Entry point: ckg.report_manager.index:main

# Debug mode
ckg_debug
```

### Celery Workers (Background Tasks)

```bash
# Project creation queue
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -Q creation

# Compute/analysis queue
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=3 -Q compute

# Database update queue
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -Q update
```

### Testing

```bash
# Run tests (uses standard library, no pytest)
python3 -m unittest discover tests/

# Test specific module
python3 tests/test_graphdb_builder.py
```

## Architecture

### Directory Structure

- **ckg/graphdb_builder/**: Database construction pipeline
  - `builder/`: Orchestrates import and loading (`importer.py`, `loader.py`, `builder.py`)
  - `databases/`: 30+ database parsers (UniProt, STRING, DrugBank, etc.)
  - `ontologies/`: Ontology parsers (Disease Ontology, GO, HPO, etc.)
  - `experiments/`: Clinical/proteomics experiment data handlers
  - `users/`: User data management

- **ckg/graphdb_connector/**: Neo4j connection management
  - `connector.py`: Database driver configuration (bolt://localhost:7687)
  - `query_utils.py`: Query execution utilities
  - `queries.yml`: Predefined Cypher queries

- **ckg/report_manager/**: Web application (Flask/Dash)
  - `index.py`: Main application entry point with routing
  - `apps/`: Dash applications (login, admin, project, data upload)
  - `worker.py`: Celery tasks for async processing
  - `dataset.py`, `project.py`, `knowledge.py`: Core domain models
  - `queries/`: Cypher queries for report generation

- **ckg/analytics_core/**: Statistical analysis engine
  - `analytics_factory.py`: Analysis orchestration (51K lines)
  - `analytics/analytics.py`: Statistical methods (147K lines)
  - `viz/`: Visualization utilities
  - `R_wrapper.py`: Interface to R via rpy2

- **ckg/config/**: Configuration management
  - Generated at runtime by `ckg/init.py`
  - Creates `ckg_config.yml` with paths and logging config

### Data Flow

1. **Import Phase** (`graphdb_builder/builder/importer.py`):
   - Downloads data from external sources (ontologies, databases)
   - Parses into standardized TSV format
   - Stores in `data/imports/` subdirectories

2. **Load Phase** (`graphdb_builder/builder/loader.py`):
   - Reads imported TSV files
   - Executes Cypher queries to create nodes/relationships in Neo4j
   - Updates graph schema

3. **Analysis Phase** (`analytics_core/analytics_factory.py`):
   - Queries graph for project data
   - Applies statistical methods (differential expression, clustering, WGCNA, etc.)
   - Generates interactive visualizations via Dash

4. **Report Generation** (`report_manager/`):
   - User creates projects via web interface
   - Uploads experimental data (proteomics, clinical)
   - Celery workers process data asynchronously
   - Results displayed in interactive Dash dashboards

### Key Integrations

- **Neo4j Plugins Required**:
  - Graph Data Science (GDS) library for graph algorithms
  - APOC for advanced Cypher procedures
  - Configure via `resources/neo4j_db/neo4j.conf`

- **Licensed Databases** (require manual download):
  - PhosphoSitePlus: Protein phosphorylation data
  - DrugBank: Drug-target interactions
  - Clinical_variable ontology: Clinical metadata

- **R Integration**:
  - WGCNA (Weighted Gene Co-expression Network Analysis)
  - Statistical tests via rpy2
  - Install R packages via `resources/R_packages.R`

## Configuration Files

- **ckg_config.yml**: Generated by `ckg/init.py`, contains all paths and logging configs
- **connector_config.yml**: Neo4j connection settings (host, port, credentials)
- **databases_config.yml**: Database parser configurations
- **ontologies_config.yml**: Ontology parser configurations
- **builder_utils.setup_config()**: Used throughout codebase to load configs

Default Neo4j credentials: neo4j/NeO4J (change in production)

## Docker Deployment

```bash
# Build image
docker build -t ckg:latest .

# Run container (exposes ports: 7474, 7687, 8090, 8050, 5000, 6379)
docker run -d -p 7474:7474 -p 7687:7687 -p 8090:8090 -p 8050:8050 ckg:latest
```

The Docker image includes:
- Pre-loaded Neo4j database dump (downloaded during build)
- All dependencies (Python 3.10, R 3.6.1, Neo4j 4.2.3)
- Auto-starts services via `docker_entrypoint.sh`: Neo4j, Redis, Celery workers, JupyterHub, nginx/uWSGI

## Development Notes

### Adding New Database Parsers

1. Create parser in `ckg/graphdb_builder/databases/parsers/`
2. Add config to `ckg/graphdb_builder/databases/config/`
3. Register in `databases_controller.py`
4. Import data: `ckg_build -u <user> -b import -i databases -d <db_name>`
5. Load into Neo4j: `ckg_build -u <user> -b load`

### Adding New Analytical Methods

1. Implement in `ckg/analytics_core/analytics/analytics.py`
2. Register in `analytics_factory.py` analysis workflow
3. Update report templates in `ckg/report_manager/apps/`

### Logging

Four separate log files configured in `ckg/config/`:
- `graphdb_builder.log`: Database construction
- `graphdb_connector.log`: Neo4j queries
- `report_manager.log`: Web application
- `analytics_factory.log`: Statistical analyses

Access via `builder_utils.setup_logging(log_config, key="<component>")`

### Common Pitfalls

- **Python version**: Originally required 3.7.9 (in setup.py), but upgraded to 3.10 in Dockerfile
- **rpy2 not available on Windows**: R integration disabled via platform check in requirements.txt
- **Neo4j dump compatibility**: Database dumps are version-specific (4.2.3)
- **Licensed databases**: PhosphoSitePlus and DrugBank require manual download and placement in `data/imports/databases/`
- **Directory permissions**: nginx user (UID 1500) needs write access to logs and data directories
