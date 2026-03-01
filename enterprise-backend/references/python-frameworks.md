# Python Backend Frameworks Reference

## Framework Selection

| Feature | FastAPI | Django | Flask |
|---|---|---|---|
| Performance | ⭐⭐⭐⭐⭐ (async) | ⭐⭐⭐ | ⭐⭐⭐ |
| Auto API Docs | Built-in (OpenAPI) | Via drf-spectacular | Manual |
| ORM | Bring your own (SQLAlchemy) | Built-in (Django ORM) | Bring your own |
| Admin Panel | No | Built-in | No |
| Validation | Pydantic (built-in) | Serializers/Forms | Manual |
| Best For | APIs, data services, ML | Full web apps, admin-heavy | Small services |

---

## FastAPI (Recommended for APIs)

### Setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install "fastapi[standard]" sqlalchemy[asyncio] alembic asyncpg redis pydantic-settings argon2-cffi python-jose httpx
pip install -D pytest pytest-asyncio pytest-cov ruff mypy
```

### Project Structure

```
src/
├── main.py                  # App entry point
├── config.py                # Settings via pydantic-settings
├── database.py              # SQLAlchemy async engine + session
├── dependencies.py          # Shared FastAPI dependencies
├── modules/
│   ├── auth/
│   │   ├── router.py
│   │   ├── service.py
│   │   ├── schemas.py       # Pydantic models
│   │   ├── models.py        # SQLAlchemy models
│   │   └── dependencies.py
│   ├── users/
│   │   ├── router.py
│   │   ├── service.py
│   │   ├── schemas.py
│   │   └── models.py
│   └── payments/
├── middleware/
│   ├── auth.py
│   ├── rate_limit.py
│   └── logging.py
├── lib/
│   ├── email.py
│   ├── redis.py
│   └── errors.py
├── tests/
│   ├── conftest.py
│   └── test_users.py
├── alembic/                 # Database migrations
└── alembic.ini
```

### App Entry Point

```python
# src/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .database import engine
from .modules.auth.router import router as auth_router
from .modules.users.router import router as users_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    yield
    # Shutdown
    await engine.dispose()

app = FastAPI(title="Enterprise API", lifespan=lifespan, docs_url="/api/docs" if settings.DEBUG else None)

app.add_middleware(CORSMiddleware, allow_origins=settings.CORS_ORIGINS, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

app.include_router(auth_router, prefix="/api/auth", tags=["auth"])
app.include_router(users_router, prefix="/api/users", tags=["users"])

@app.get("/health")
async def health():
    return {"status": "healthy"}
```

### Configuration

```python
# src/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DEBUG: bool = False
    DATABASE_URL: str
    REDIS_URL: str
    JWT_SECRET: str
    CORS_ORIGINS: list[str] = ["http://localhost:3000"]
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""
    RESEND_API_KEY: str = ""

    class Config:
        env_file = ".env"

settings = Settings()
```

### Database Setup (Async SQLAlchemy)

```python
# src/database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase

engine = create_async_engine(settings.DATABASE_URL, pool_size=20, max_overflow=10, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session
```

### Router Pattern

```python
# src/modules/users/router.py
from fastapi import APIRouter, Depends, Query
from .service import UsersService
from .schemas import UserCreate, UserResponse, UserListResponse
from ..auth.dependencies import require_auth, require_role

router = APIRouter()

@router.get("/", response_model=UserListResponse)
async def list_users(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    search: str | None = None,
    user=Depends(require_auth),
    service: UsersService = Depends(),
):
    return await service.list(page=page, limit=limit, search=search)

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: str, user=Depends(require_auth), service: UsersService = Depends()):
    return await service.get_by_id(user_id)

@router.post("/", response_model=UserResponse, status_code=201)
async def create_user(
    data: UserCreate,
    user=Depends(require_role("admin")),
    service: UsersService = Depends(),
):
    return await service.create(data)
```

### Pydantic Schemas

```python
# src/modules/users/schemas.py
from pydantic import BaseModel, EmailStr
from datetime import datetime
from enum import Enum

class UserRole(str, Enum):
    admin = "admin"
    user = "user"
    viewer = "viewer"

class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=100)
    role: UserRole

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    role: UserRole
    created_at: datetime

    class Config:
        from_attributes = True

class UserListResponse(BaseModel):
    users: list[UserResponse]
    total: int
    page: int
    limit: int
```

### Service Layer

```python
# src/modules/users/service.py
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from ...database import get_db
from ...lib.errors import NotFoundError, ConflictError
from .models import User
from .schemas import UserCreate
import logging

logger = logging.getLogger(__name__)

class UsersService:
    def __init__(self, db: AsyncSession = Depends(get_db)):
        self.db = db

    async def list(self, page: int, limit: int, search: str | None = None):
        query = select(User).where(User.deleted_at.is_(None))
        if search:
            query = query.where(User.name.ilike(f"%{search}%"))

        total = await self.db.scalar(select(func.count()).select_from(query.subquery()))
        users = (await self.db.scalars(query.offset((page-1)*limit).limit(limit).order_by(User.created_at.desc()))).all()

        return {"users": users, "total": total, "page": page, "limit": limit}

    async def get_by_id(self, user_id: str):
        user = await self.db.get(User, user_id)
        if not user or user.deleted_at:
            raise NotFoundError("User")
        return user

    async def create(self, data: UserCreate):
        existing = await self.db.scalar(select(User).where(User.email == data.email))
        if existing:
            raise ConflictError("Email already in use")

        user = User(**data.model_dump())
        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)
        logger.info(f"User created: {user.id}")
        return user
```

### Auth Dependency

```python
# src/modules/auth/dependencies.py
from fastapi import Depends, HTTPException, Request
from ...lib.auth import verify_session

async def require_auth(request: Request):
    token = request.cookies.get("session")
    if not token:
        raise HTTPException(401, "Authentication required")
    user = await verify_session(token)
    if not user:
        raise HTTPException(401, "Invalid or expired session")
    return user

def require_role(*roles: str):
    async def dependency(user=Depends(require_auth)):
        if user.role not in roles:
            raise HTTPException(403, "Insufficient permissions")
        return user
    return dependency
```

---

## Django (Full-Featured Web Apps)

### Setup
```bash
pip install django djangorestframework django-cors-headers django-filter drf-spectacular argon2-cffi
django-admin startproject config .
python manage.py startapp users
```

### DRF ViewSet Pattern
```python
# users/views.py
from rest_framework import viewsets, permissions, filters
from django_filters.rest_framework import DjangoFilterBackend
from .models import User
from .serializers import UserSerializer

class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.filter(deleted_at__isnull=True)
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['name', 'email']
    ordering_fields = ['created_at', 'name']
    ordering = ['-created_at']

    def get_permissions(self):
        if self.action in ['create', 'destroy']:
            return [permissions.IsAdminUser()]
        return super().get_permissions()

    def perform_destroy(self, instance):
        instance.deleted_at = timezone.now()
        instance.save()
```

---

## Testing

```python
# tests/test_users.py
import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app

@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

@pytest.mark.asyncio
async def test_list_users_requires_auth(client):
    res = await client.get("/api/users/")
    assert res.status_code == 401

@pytest.mark.asyncio
async def test_create_user_validates_input(client, auth_cookies):
    res = await client.post("/api/users/", json={"email": "invalid"}, cookies=auth_cookies)
    assert res.status_code == 422
```
