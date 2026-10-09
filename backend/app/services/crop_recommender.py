"""
Deterministic Crop Recommender Engine for KisanMausam
Evaluates soil, terrain, irrigation, season, and Risk Engine Horizon 3 seasonal outlook.
Ranks crops deterministically and produces Hindi reasons, risk warnings, and drought-tolerant alternatives.
"""

from typing import List, Dict, Any, Optional
from datetime import datetime, date
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.crop import Crop
from app.models.farm import Farm
from app.services.crop_seed_data import SEED_CROPS
import logging

logger = logging.getLogger("kishan_mausam.crop_recommender")

async def seed_crops_if_empty(db: AsyncSession) -> int:
    """Populate crops table with the 30 initial crops if empty."""
    result = await db.execute(select(Crop))
    existing = result.scalars().first()
    if existing is not None:
        return 0
    
    count = 0
    for crop_dict in SEED_CROPS:
        crop = Crop(**crop_dict)
        db.add(crop)
        count += 1
    await db.commit()
    logger.info(f"Successfully seeded {count} crops into database.")
    return count

def derive_current_season(current_date: Optional[date] = None) -> Dict[str, Any]:
    """
    Derives active agricultural season from current date in India:
    - Kharif: June to October (Monsoon)
    - Rabi: October to March (Winter)
    - Zaid: March to June (Summer)
    October is transition: Kharif harvesting and Rabi sowing.
    March is transition: Rabi harvesting and Zaid sowing.
    """
    if current_date is None:
        current_date = date.today()
    
    month = current_date.month
    day = current_date.day

    if 6 <= month <= 9:
        return {"primary": "kharif", "secondary": None, "name_hi": "खरीफ (Kharif)", "name_en": "Kharif (Monsoon)"}
    elif month == 10:
        return {"primary": "rabi", "secondary": "kharif", "name_hi": "रबी बुवाई (Rabi Transition)", "name_en": "Rabi Sowing / Kharif Harvest"}
    elif 11 <= month or month <= 2:
        return {"primary": "rabi", "secondary": None, "name_hi": "रबी (Rabi)", "name_en": "Rabi (Winter)"}
    elif month == 3:
        return {"primary": "zaid", "secondary": "rabi", "name_hi": "जायद बुवाई (Zaid Sowing)", "name_en": "Zaid Summer Sowing"}
    else:  # April, May
        return {"primary": "zaid", "secondary": None, "name_hi": "जायद (Zaid)", "name_en": "Zaid (Summer)"}

class CropRecommenderService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def recommend_crops(
        self,
        farm: Farm,
        below_normal_rain_prob: float = 35.0,
        above_normal_temp_prob: float = 35.0,
        eval_date: Optional[date] = None,
    ) -> Dict[str, Any]:
        """
        Deterministic recommendation of top 5 crops based on farm characteristics and seasonal climate outlook.
        """
        # Ensure crops exist
        await seed_crops_if_empty(self.db)

        season_info = derive_current_season(eval_date)
        primary_season = season_info["primary"]
        secondary_season = season_info["secondary"]

        # Fetch all crops
        query = await self.db.execute(select(Crop))
        all_crops = query.scalars().all()

        scored_crops = []

        for crop in all_crops:
            score = 0
            reasons_hi = []
            risk_notes_hi = []

            # 1. Season Match (Max 40 points)
            if crop.season == primary_season:
                score += 40
                reasons_hi.append(f"वर्तमान समय ({season_info['name_hi']}) इस फसल की बुवाई के लिए पूर्णतः अनुकूल है।")
            elif secondary_season and crop.season == secondary_season:
                score += 25
                reasons_hi.append(f"संक्रमण काल होने से इस मौसम में भी खेती संभव है।")
            elif crop.season == "perennial":
                score += 20
                reasons_hi.append("यह बहुवर्षीय फसल है, जिसे उचित सिंचाई पर लगाया जा सकता है।")
            else:
                score += 5  # Non-matching season gets minimal score

            # 2. Soil Match (Max 25 points)
            farm_soil = (farm.soil_type or "").lower()
            if farm_soil == "dont_know":
                score += 15
                reasons_hi.append("अधिकांश सामान्य भारतीय मिट्टियों में उत्पादक।")
            elif farm_soil in [s.lower() for s in (crop.suitable_soils or [])]:
                score += 25
                soil_trans = {
                    "alluvial": "जलोढ़ (Alluvial)",
                    "black": "काली कपासी (Black Soil)",
                    "red": "लाल (Red Soil)",
                    "sandy": "बलुई (Sandy)",
                    "loamy": "दोमट (Loamy)"
                }.get(farm_soil, farm_soil)
                reasons_hi.append(f"आपके खेत की {soil_trans} मिट्टी इस फसल के लिए आदर्श पोषक तत्व प्रदान करती है।")
            else:
                score += 5
                risk_notes_hi.append(f"यह फसल मुख्य रूप से {', '.join(crop.suitable_soils)} मिट्टी पसंद करती है।")

            # 3. Terrain Match (Max 15 points)
            farm_terrain = (farm.terrain or "").lower()
            if farm_terrain in [t.lower() for t in (crop.suitable_terrains or [])]:
                score += 15
                terrain_trans = {
                    "plain": "मैदानी (Plain)",
                    "plateau": "पठारी (Plateau)",
                    "hilly": "पहाड़ी (Hilly)",
                    "coastal": "तटीय (Coastal)",
                    "barren_dry": "शुष्क/बंजर (Dryland)"
                }.get(farm_terrain, farm_terrain)
                reasons_hi.append(f"{terrain_trans} भूभाग के ढलान व जल निकास से मेल खाती है।")
            else:
                score += 5

            # 4. Irrigation Compatibility (Max 20 points, with penalties)
            farm_irrigation = (farm.irrigation_type or "").lower()
            if farm_irrigation == "rainfed":
                if crop.irrigation_need == "low":
                    score += 20
                    reasons_hi.append("कम पानी की आवश्यकता: असिंचित / वर्षा-आधारित खेत के लिए सर्वोत्तम सुरक्षित विकल्प।")
                elif crop.irrigation_need == "medium":
                    score += 5
                    risk_notes_hi.append("मध्यम पानी की आवश्यकता: फूल व दाना बनते समय कम से कम 1-2 जीवन रक्षक सिंचाइयों की आवश्यकता होगी।")
                else:  # high
                    score -= 25
                    risk_notes_hi.append("अधिक पानी की आवश्यकता: केवल वर्षा पर निर्भर खेत में भारी उत्पादन हानि का जोखिम।")
            else:  # tubewell or canal
                if crop.irrigation_need in ["medium", "high"]:
                    score += 18
                    reasons_hi.append("सुनिश्चित सिंचाई (ट्यूबवेल/नहर) उपलब्ध होने से उच्च उत्पादन क्षमता।")
                else:
                    score += 15
                    reasons_hi.append("कम जल खपत के कारण सिंचाई लागत व बिजली की बचत।")

            # 5. Seasonal Risk / Climate Outlook Modifier (Horizon 3 anomaly)
            # If below-normal rainfall is >= 35%, reward drought tolerance, penalize water hunger
            if below_normal_rain_prob >= 35.0:
                if crop.drought_tolerance == "high":
                    score += 15
                    reasons_hi.append(f"30-दिवसीय मौसम रुझान (कम वर्षा संभावना {below_normal_rain_prob}%) को देखते हुए सूखा-सहनशील (Drought Tolerant) गुण सुरक्षित रहेगा।")
                elif crop.drought_tolerance == "medium":
                    score += 5
                elif crop.drought_tolerance == "low":
                    score -= 15
                    risk_notes_hi.append(f"आगामी 30 दिनों में वर्षा की कमी ({below_normal_rain_prob}%) रहने पर इस फसल में जल तनाव आ सकता है।")

            # Frost resilience check for winter
            if primary_season == "rabi" and crop.frost_tolerance == "low":
                risk_notes_hi.append("दिसंबर-जनवरी में पाला पड़ने पर फसल को नुकसान हो सकता है (पाला सुरक्षा आवश्यक)।")

            # Calculate normalized match percentage (0 - 100)
            match_percentage = max(10, min(98, score))

            # Suggest drought tolerant alternative if risky
            drought_alt = None
            if crop.drought_tolerance == "low" or (crop.irrigation_need == "high" and farm_irrigation == "rainfed"):
                drought_alt = "चना (Gram) या सरसों (Mustard)" if primary_season == "rabi" else "बाजरा (Bajra) या मूंग (Moong)"

            scored_crops.append({
                "crop_id": crop.id,
                "name_hi": crop.name_hi,
                "name_en": crop.name_en,
                "season": crop.season,
                "match_score": match_percentage,
                "irrigation_need": crop.irrigation_need,
                "drought_tolerance": crop.drought_tolerance,
                "frost_tolerance": crop.frost_tolerance,
                "flood_tolerance": crop.flood_tolerance,
                "duration_days": f"{crop.duration_days_min}-{crop.duration_days_max} दिन",
                "water_need_mm": crop.water_need_mm_season,
                "reasons": reasons_hi,
                "risk_notes": risk_notes_hi,
                "drought_tolerant_alternative": drought_alt,
                "source_citation": crop.source_citation,
                "needs_expert_review": crop.needs_expert_review,
            })

        # Rank and take Top 5
        scored_crops.sort(key=lambda x: x["match_score"], reverse=True)
        top_5 = scored_crops[:5]
        for idx, item in enumerate(top_5, 1):
            item["rank"] = idx

        return {
            "farm_id": farm.id,
            "farm_name": farm.name,
            "village": farm.village,
            "district": farm.district,
            "current_season": season_info["name_hi"],
            "season_en": season_info["name_en"],
            "climate_outlook": {
                "source": "Open-Meteo Seasonal ECMWF EC46 / SEAS5",
                "horizon": "10-46 Days Seasonal Outlook",
                "below_normal_rain_probability": below_normal_rain_prob,
                "above_normal_temp_probability": above_normal_temp_prob,
                "summary_hi": f"आगामी 30 दिनों में उमरेड/क्षेत्र में सामान्य से कम वर्षा होने की संभावना {below_normal_rain_prob}% है।"
            },
            "recommendations": top_5,
            "disclaimer_hi": "ये सिफारिशें ICAR एवं राज्य कृषि विश्वविद्यालय के पैकेज ऑफ प्रैक्टिसेज के सामान्य मानकों पर आधारित हैं। बुवाई से पूर्व मिट्टी परीक्षण व स्थानीय कृषि विज्ञान केंद्र (KVK Toll-Free: 1800-180-1551) से परामर्श अवश्य लें।",
            "needs_expert_review": True
        }
