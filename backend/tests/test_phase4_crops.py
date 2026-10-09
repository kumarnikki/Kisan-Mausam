import pytest
from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.models.crop import Crop
from app.models.farm import Farm
from app.models.user import User
from app.services.crop_recommender import (
    seed_crops_if_empty,
    derive_current_season,
    CropRecommenderService
)
from app.services.crop_seed_data import SEED_CROPS

@pytest.mark.asyncio
async def test_crop_seeding_and_expert_review_flag(async_session: AsyncSession):
    """Verify that 30 crops are seeded into knowledge base and all are flagged needs_expert_review=True."""
    count = await seed_crops_if_empty(async_session)
    
    # Query database
    result = await async_session.execute(select(Crop))
    crops = result.scalars().all()
    
    assert len(crops) == 30
    assert len(SEED_CROPS) == 30
    
    # Check every crop has needs_expert_review True and valid citations
    for c in crops:
        assert c.needs_expert_review is True
        assert c.source_citation is not None
        assert len(c.source_citation) > 5
        assert c.name_hi is not None
        assert c.name_en is not None
        assert c.season in ["kharif", "rabi", "zaid", "perennial"]

def test_season_derivation():
    """Verify correct agro-climatic season derivation across calendar dates."""
    # July (Monsoon / Kharif)
    s_july = derive_current_season(date(2026, 7, 15))
    assert s_july["primary"] == "kharif"
    
    # October (Rabi sowing transition)
    s_oct = derive_current_season(date(2026, 10, 10))
    assert s_oct["primary"] == "rabi"
    assert s_oct["secondary"] == "kharif"

    # December (Winter / Rabi peak)
    s_dec = derive_current_season(date(2026, 12, 1))
    assert s_dec["primary"] == "rabi"

    # April (Summer / Zaid)
    s_apr = derive_current_season(date(2026, 4, 20))
    assert s_apr["primary"] == "zaid"

@pytest.mark.asyncio
async def test_deterministic_recommender_scoring(async_session: AsyncSession):
    """
    Test deterministic recommendation scoring:
    In Rabi season with dry spell outlook (below_normal_rain_prob=45%),
    a rainfed farm with black soil must rank drought-tolerant pulses/oilseeds (Gram/Mustard)
    above water-hungry crops (like Potato or Sugarcane).
    """
    await seed_crops_if_empty(async_session)

    # Create test user and rainfed farm
    test_user = User(phone_number="+919871112233")
    async_session.add(test_user)
    await async_session.commit()
    await async_session.refresh(test_user)

    test_farm = Farm(
        user_id=test_user.id,
        name="सूखा प्रवण खेत",
        village="उमरेड",
        district="नागपुर",
        state="Maharashtra",
        latitude=20.85,
        longitude=79.32,
        terrain="plateau",
        soil_type="black",
        irrigation_type="rainfed",
        current_crop="सोयाबीन",
        sowing_date=date(2026, 7, 1)
    )
    async_session.add(test_farm)
    await async_session.commit()
    await async_session.refresh(test_farm)

    recommender = CropRecommenderService(async_session)
    res = await recommender.recommend_crops(
        farm=test_farm,
        below_normal_rain_prob=45.0, # High dry spell risk
        eval_date=date(2026, 10, 15) # Rabi sowing
    )

    assert "recommendations" in res
    assert len(res["recommendations"]) == 5
    assert res["needs_expert_review"] is True
    assert "KVK" in res["disclaimer_hi"]

    top_recs = res["recommendations"]
    top_names_hi = [r["name_hi"] for r in top_recs]
    
    # Gram (चना) or Mustard (सरसों) or Linseed (अलसी) should rank near top because black soil + rainfed + dry spell
    assert any("चना" in name or "सरसों" in name or "अलसी" in name for name in top_names_hi)
    
    # Top crop should have high score
    assert top_recs[0]["match_score"] >= 70
    assert len(top_recs[0]["reasons"]) > 0

@pytest.mark.asyncio
async def test_recommender_endpoint_integration(async_session: AsyncSession):
    """Verify GET /farms/{farm_id}/crops/recommendations and GET /crops/database endpoints."""
    await seed_crops_if_empty(async_session)

    user = User(phone_number="+919874445566")
    async_session.add(user)
    await async_session.commit()
    await async_session.refresh(user)

    farm = Farm(
        user_id=user.id,
        name="हरित प्रक्षेत्र",
        village="काटोल",
        district="नागपुर",
        state="Maharashtra",
        latitude=21.26,
        longitude=78.58,
        terrain="plain",
        soil_type="alluvial",
        irrigation_type="tubewell",
        current_crop="कपास",
        sowing_date=date(2026, 6, 25)
    )
    async_session.add(farm)
    await async_session.commit()
    await async_session.refresh(farm)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Test recommendation endpoint
        resp = await ac.get(f"/farms/{farm.id}/crops/recommendations")
        assert resp.status_code == 200
        data = resp.json()
        assert data["farm_id"] == farm.id
        assert len(data["recommendations"]) == 5
        assert data["needs_expert_review"] is True

        # Test crop database listing
        db_resp = await ac.get("/crops/database")
        assert db_resp.status_code == 200
        crops_list = db_resp.json()
        assert len(crops_list) == 30
