import pytest_asyncio
from app.database import engine, Base, AsyncSessionLocal

@pytest_asyncio.fixture(autouse=True)
async def setup_test_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    # Keep db or teardown

@pytest_asyncio.fixture
async def async_session():
    async with AsyncSessionLocal() as session:
        yield session
