from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Date
from datetime import datetime
from app.database import Base

class Farm(Base):
    __tablename__ = "farms"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    name = Column(String(100), nullable=False)
    
    # Location
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    village = Column(String(100), nullable=True)
    district = Column(String(100), nullable=True)
    state = Column(String(100), nullable=True)
    
    # Land & Agricultural characteristics
    terrain = Column(String(50), nullable=False, default="plain")  # hilly, plain, plateau, coastal, barren-dry
    soil_type = Column(String(50), nullable=False, default="alluvial")  # alluvial, black, red, sandy, loamy, unknown
    irrigation_type = Column(String(50), nullable=False, default="rain-fed")  # rain-fed, tube-well, canal
    land_size_acres = Column(Float, default=2.0)
    
    # Current Crop
    current_crop = Column(String(100), nullable=True)
    crop_stage = Column(String(50), default="vegetative")  # sowing, vegetative, flowering, grain_fill, harvest
    sowing_date = Column(Date, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
