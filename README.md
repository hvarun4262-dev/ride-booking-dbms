# Ride Booking DBMS

A ride-booking backend built using **Python, FastAPI, PostgreSQL, and SQLAlchemy**. This project models the core operations of a ride-booking platform, including ride requests, driver assignment, ride status management, payments, ratings, and analytics.

## Features

- **Relational database design:** Tables for riders, drivers, rides, payments, ratings, and ride status history.
- **Database constraints:** Uses primary keys, foreign keys, unique constraints, and checks to maintain data integrity.
- **Indexes:** Improves query performance for common database operations.
- **Database triggers:** Automates selected database operations and enforces business rules.
- **Ride management:** Provides API routes for ride-related operations.
- **Analytics:** Includes a separate analytics route module.
- **Concurrency testing:** Includes a test script for examining concurrent ride-booking operations.
- **API documentation:** FastAPI provides interactive documentation through Swagger UI.
- **Docker support:** Docker Compose configuration for running PostgreSQL.

## Tech Stack

- **Language:** Python
- **Backend framework:** FastAPI
- **Database:** PostgreSQL
- **ORM:** SQLAlchemy
- **Database driver:** psycopg2
- **Server:** Uvicorn
- **Containerization:** Docker Compose
- **Testing:** Python concurrency test script

## Project Structure

```text
ride-booking-dbms/
├── app/
│   ├── __init__.py
│   ├── db.py
│   ├── main.py
│   └── routes/
│       ├── __init__.py
│       ├── rides.py
│       └── analytics.py
├── database/
│   ├── 01_schema.sql
│   ├── 02_indexes.sql
│   ├── 03_triggers.sql
│   ├── 04_seed_data.sql
│   └── 05_complex_queries.sql
├── docs/
├── scripts/
│   └── test_concurrency.py
├── .env
├── .env.example
├── .gitignore
├── docker-compose.yml
├── requirements.txt
├── LICENSE
└── README.md
```

> `venv/` and `venv-linux/` are local Python virtual environments and should not be committed to Git. Python cache files such as `__pycache__/` should also be excluded.

## Prerequisites

Install the following before running the project:

- Python 3.10 or later
- PostgreSQL, or Docker Desktop with Docker Compose
- Git

## Setup and Installation

### 1. Clone the repository

```bash
git clone https://github.com/hvarun4262-dev/ride-booking-dbms.git
cd ride-booking-dbms
```

### 2. Configure environment variables

The project contains `.env.example` as a template for local configuration.

Copy it to `.env` if you have not already created your local environment file.

**Windows PowerShell:**

```powershell
Copy-Item .env.example .env
```

**Linux or WSL:**

```bash
cp .env.example .env
```

Open `.env` and configure `DATABASE_URL` to match your PostgreSQL credentials and database name.

Example:

```env
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/ride_booking_db
```

Replace `YOUR_PASSWORD` with the password that actually works for your PostgreSQL instance. Do not commit `.env` or put real credentials in this README.

### 3. Start PostgreSQL

From the project root, run:

```bash
docker compose up -d
```

Check the container status:

```bash
docker compose ps
```

If PostgreSQL was initialized previously, changing `POSTGRES_PASSWORD` in `docker-compose.yml` does not automatically change the password stored in the existing database volume. Configure `.env` using the password that the existing database accepts.

### 4. Create the database schema

Connect to the `ride_booking_db` database using your preferred PostgreSQL client, such as `psql`, pgAdmin, or VS Code's PostgreSQL extension.

Run the SQL files in this order:

1. `database/01_schema.sql` — creates the database tables, types, and constraints.
2. `database/02_indexes.sql` — creates indexes for frequently used queries.
3. `database/03_triggers.sql` — defines database trigger functions and triggers.
4. `database/04_seed_data.sql` — inserts sample data.
5. `database/05_complex_queries.sql` — contains complex SQL queries for analysis.

Run the schema, indexes, triggers, and seed data scripts only when appropriate for your database's current state. **The seed script may create duplicate data or reset existing data, depending on its contents. Inspect it before running it against a database you want to preserve.**

The fifth file contains queries for analysis; it does not necessarily need to be executed as part of initial database setup.

### 5. Set up Python

Create and activate a virtual environment if you do not already have one.

**Windows PowerShell:**

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

**Linux or WSL:**

```bash
python3 -m venv venv-linux
source venv-linux/bin/activate
```

Install the project dependencies:

```bash
python -m pip install -r requirements.txt
```

Make sure the packages required by the application, including FastAPI, Uvicorn, SQLAlchemy, and the PostgreSQL driver, are listed in `requirements.txt`.

### 6. Run the API

From the project root, start the FastAPI application:

```bash
python -m uvicorn app.main:app --reload
```

Once the server starts, open the following URLs in your browser:

| Resource | URL |
|---|---|
| Interactive API documentation | http://127.0.0.1:8000/docs |
| Alternative API documentation | http://127.0.0.1:8000/redoc |
| Local API server | http://127.0.0.1:8000 |

Use the endpoints displayed in Swagger UI to explore and test the routes implemented in the project.

## Database Design

The database is organized around six core entities:

- **Riders:** Stores rider information.
- **Drivers:** Stores driver information and vehicle-related details.
- **Rides:** Stores ride requests, ride details, and status information.
- **Payments:** Stores payment records associated with rides.
- **Ratings:** Stores feedback associated with completed rides, subject to the implemented validation rules.
- **Ride Status History:** Records changes to ride status.

The relationships are represented through primary keys and foreign keys defined in the schema.

## SQL Components

| File | Purpose |
|---|---|
| `01_schema.sql` | Database schema and constraints |
| `02_indexes.sql` | Query-performance indexes |
| `03_triggers.sql` | Trigger functions and automated database rules |
| `04_seed_data.sql` | Sample data for development and testing |
| `05_complex_queries.sql` | Advanced SQL queries and analytics |

## API Modules

The API code is organized into separate modules:

- `app/main.py` — application entry point and route registration.
- `app/db.py` — database engine, session configuration, and database connection dependencies.
- `app/routes/rides.py` — ride-related API operations.
- `app/routes/analytics.py` — analytics-related API operations.

For the exact endpoints, request formats, and response structures, refer to the running Swagger documentation at `/docs`.

## Testing

The repository includes:

```text
scripts/test_concurrency.py
```

This script is intended for testing concurrent booking-related behavior. Review the script to understand its database requirements and how it creates test scenarios before running it.

Run it using the Python environment configured for the project:

```bash
python scripts/test_concurrency.py
```

Ensure that PostgreSQL is running and that the test uses the correct database configuration. Use a development database with disposable test data rather than production data.


## License

See the `LICENSE` file for licensing information.
