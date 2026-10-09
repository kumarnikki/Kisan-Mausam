from sqlalchemy import Column, Integer, String, Float, Boolean, JSON, DateTime
from datetime import datetime
from app.database import Base

class Crop(Base):
    __tablename__ = "crops"

    id = Column(Integer, primary_key=True, index=True)
    name_hi = Column(String(100), nullable=False, index=True)
    name_en = Column(String(100), nullable=False, index=True)
    season = Column(String(50), nullable=False)  # kharif, rabi, zaid, perennial
    
    # Suitability filters
    suitable_terrains = Column(JSON, nullable=False)  # ["plain", "plateau", etc.]
    suitable_soils = Column(JSON, nullable=False)     # ["alluvial", "black", etc.]
    irrigation_need = Column(String(50), nullable=False)  # low, medium, high
    
    # Resilience characteristics
    drought_tolerance = Column(String(50), default="medium")  # low, medium, high
    flood_tolerance = Column(String(50), default="low")       # low, medium, high
    frost_tolerance = Column(String(50), default="low")       # low, medium, high
    
    duration_days_min = Column(Integer, default=90)
    duration_days_max = Column(Integer, default=120)
    sowing_temp_min_c = Column(Float, default=15.0)
    sowing_temp_max_c = Column(Float, default=35.0)
    water_need_mm_season = Column(Float, default=500.0)
    
    source_citation = Column(String(250), default="ICAR Agronomy Handbook & State Agricultural University Package of Practices")
    needs_expert_review = Column(Boolean, default=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)
