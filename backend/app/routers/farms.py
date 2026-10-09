from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from typing import List
from app.database import get_db
from app.models.user import User
from app.models.farm import Farm
from app.schemas.farm import FarmCreate, FarmUpdate, FarmResponse
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/farms", tags=["Farms"])

@router.post("", response_model=FarmResponse)
async def create_farm(
    farm_in: FarmCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Check limit of 3 farms per user
    result = await db.execute(select(Farm).where(Farm.user_id == current_user.id))
    farms = result.scalars().all()
    if len(farms) >= 3:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Maximum 3 farms allowed per account"
        )

    new_farm = Farm(
        user_id=current_user.id,
        **farm_in.model_dump()
    )
    db.add(new_farm)
    await db.commit()
    await db.refresh(new_farm)
    return new_farm

@router.get("", response_model=List[FarmResponse])
async def list_farms(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Farm).where(Farm.user_id == current_user.id))
    return result.scalars().all()

@router.get("/{farm_id}", response_model=FarmResponse)
async def get_farm(
    farm_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Farm).where(Farm.id == farm_id, Farm.user_id == current_user.id))
    farm = result.scalars().first()
    if not farm:
        raise HTTPException(status_code=404, detail="Farm not found")
    return farm

@router.put("/{farm_id}", response_model=FarmResponse)
async def update_farm(
    farm_id: int,
    farm_update: FarmUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Farm).where(Farm.id == farm_id, Farm.user_id == current_user.id))
    farm = result.scalars().first()
    if not farm:
        raise HTTPException(status_code=404, detail="Farm not found")

    update_dict = farm_update.model_dump(exclude_unset=True)
    for k, v in update_dict.items():
        setattr(farm, k, v)

    await db.commit()
    await db.refresh(farm)
    return farm

@router.delete("/{farm_id}")
async def delete_farm(
    farm_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Farm).where(Farm.id == farm_id, Farm.user_id == current_user.id))
    farm = result.scalars().first()
    if not farm:
        raise HTTPException(status_code=404, detail="Farm not found")

    await db.delete(farm)
    await db.commit()
    return {"status": "success", "message": f"Farm {farm_id} deleted"}
