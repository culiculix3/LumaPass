from collections.abc import Iterator

from fastapi import HTTPException
from psycopg import Connection
from psycopg.errors import Error as PsycopgError
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout

from .settings import settings

pool: ConnectionPool | None = None


def open_pool() -> None:
    global pool
    if not settings.database_url:
        return
    pool = ConnectionPool(
        conninfo=settings.database_url,
        min_size=1,
        max_size=10,
        timeout=5,
        kwargs={
            "row_factory": dict_row,
            "connect_timeout": 5,
            "application_name": "lumapass-api",
        },
        open=False,
    )
    pool.open(wait=True, timeout=8)
    try:
        with pool.connection(timeout=3) as connection:
            connection.execute("SELECT 1 FROM users LIMIT 0")
    except PsycopgError as error:
        close_pool()
        raise RuntimeError(
            "La base de datos no está lista. Aplica "
            "backend/sql/001_schema.sql antes de iniciar la API."
        ) from error


def close_pool() -> None:
    global pool
    if pool is not None:
        pool.close()
        pool = None


def get_connection() -> Iterator[Connection]:
    if pool is None:
        raise HTTPException(status_code=503, detail="La base de datos no está configurada.")
    try:
        with pool.connection(timeout=5) as connection:
            yield connection
    except PoolTimeout as error:
        raise HTTPException(
            status_code=503, detail="El servicio está ocupado. Inténtalo de nuevo."
        ) from error


def require_ready_connection() -> ConnectionPool:
    if pool is None:
        raise HTTPException(status_code=503, detail="La base de datos no está configurada.")
    return pool
