import hashlib
import secrets
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from psycopg import Connection

from .database import get_connection
from .settings import settings

bearer = HTTPBearer(auto_error=False)
jwks_client = PyJWKClient(settings.apple_jwks_url, cache_keys=True, timeout=5)
UserConnection = Annotated[Connection, Depends(get_connection)]
BearerCredentials = Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]


def _apple_subject(token: str) -> str:
    if not settings.apple_auth_ready():
        raise HTTPException(status_code=503, detail="El inicio con Apple no está configurado.")
    try:
        key = jwks_client.get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=settings.apple_auth_audience,
            issuer=settings.apple_auth_issuer,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
        apple_subject = claims["sub"]
        if not isinstance(apple_subject, str) or not apple_subject:
            raise jwt.InvalidTokenError("Missing Apple subject.")
    except jwt.PyJWKClientConnectionError as error:
        raise HTTPException(
            status_code=503,
            detail="No se pudo verificar la identidad con Apple. Inténtalo más tarde.",
        ) from error
    except (jwt.PyJWTError, jwt.InvalidKeyError, KeyError) as error:
        raise HTTPException(
            status_code=401, detail="El token de Sign in with Apple no es válido."
        ) from error
    return apple_subject


def _user_id(connection: Connection, apple_subject: str) -> str:
    row = connection.execute(
        """
        INSERT INTO users (apple_subject) VALUES (%s)
        ON CONFLICT (apple_subject) DO UPDATE SET apple_subject = EXCLUDED.apple_subject
        WHERE users.deleted_at IS NULL
        RETURNING id
        """,
        (apple_subject,),
    ).fetchone()
    if row is None:
        raise HTTPException(
            status_code=403,
            detail="Esta cuenta se ha eliminado. Vuelve a iniciar sesión con Apple.",
        )
    return str(row["id"])


def authenticated_user(credentials: BearerCredentials, connection: UserConnection) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Inicia sesión con Apple para continuar.",
        )
    return _user_id(connection, _apple_subject(credentials.credentials))


def optional_authenticated_user(
    credentials: BearerCredentials, connection: UserConnection
) -> str | None:
    if credentials is None:
        return None
    if credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="El tipo de autenticación no es válido.")
    return _user_id(connection, _apple_subject(credentials.credentials))


def require_admin(token: str | None) -> None:
    expected = settings.admin_bearer_token
    if not expected:
        raise HTTPException(status_code=503, detail="La consola de moderación no está configurada.")
    supplied = (token or "").removeprefix("Bearer ")
    if not secrets.compare_digest(
        hashlib.sha256(supplied.encode()).digest(), hashlib.sha256(expected.encode()).digest()
    ):
        raise HTTPException(
            status_code=401, detail="No tienes autorización para moderar contenido."
        )
