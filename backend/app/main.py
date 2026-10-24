from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse

from .api import admin_dashboard_path, apple_wallet_router, router
from .database import close_pool, open_pool
from .settings import settings


@asynccontextmanager
async def lifespan(_: FastAPI):
    if settings.environment == "production" and not settings.database_url:
        raise RuntimeError("DATABASE_URL es obligatorio en producción.")
    if settings.environment == "production" and not settings.public_base_url.startswith("https://"):
        raise RuntimeError("PUBLIC_BASE_URL debe usar HTTPS en producción.")
    if settings.database_url:
        open_pool()
    yield
    close_pool()


app = FastAPI(
    title="LumaPass API",
    version="1.0.0",
    description=(
        "API privada para pases legítimos de Apple Wallet, borradores, "
        "fondos de la comunidad y actualizaciones oficiales de PassKit."
    ),
    lifespan=lifespan,
    docs_url="/api/docs" if settings.environment != "production" else None,
    redoc_url=None,
    openapi_url="/api/openapi.json",
)

if settings.allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept"],
        expose_headers=["Content-Disposition", "Last-Modified"],
        max_age=600,
    )


@app.middleware("http")
async def enforce_request_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            request_bytes = int(content_length)
        except ValueError:
            return JSONResponse(
                {"detail": "La cabecera de tamaño de solicitud no es válida."},
                status_code=status.HTTP_400_BAD_REQUEST,
            )
        if request_bytes > settings.max_upload_bytes * 2:
            return JSONResponse(
                {"detail": "La solicitud supera el tamaño máximo permitido."},
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            )
    return await call_next(request)


app.include_router(router)
app.include_router(apple_wallet_router)


@app.get(
    "/admin",
    response_class=HTMLResponse,
    include_in_schema=False,
)
def admin_dashboard() -> HTMLResponse:
    path = Path(admin_dashboard_path())
    return HTMLResponse(path.read_text(encoding="utf-8"), headers={"Cache-Control": "no-store"})
