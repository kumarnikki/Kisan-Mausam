import os
import httpx
import logging
from typing import Dict, Any, List, Optional
from app.config import settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT_TEMPLATE = """
आप "किसान मौसम कृषि सहायक" (KisanMausam Krishi Sahayak) हैं — भारतीय कृषि अनुसंधान परिषद (ICAR) और राज्य कृषि विश्वविद्यालयों के सर्वोत्तम मानकों पर प्रशिक्षित, अत्यंत आदरणीय, अनुभवी और संवेदनशील कृषि वैज्ञानिक व मौसम सलाहकार।

आपका कार्य भारतीय किसान भाइयों-बहनों को उनके खेत के वास्तविक मौसम, भू-भाग, मिट्टी के प्रकार, ऋतु (खरीफ/रबी/जायद), फसल की अवस्था और आगामी आपदा जोखिमों के अनुसार व्यावहारिक, वैज्ञानिक एवं सजीव मार्गदर्शन देना है।

【खेत व मौसम की वास्तविक स्थिति (Strict Grounding Data)】:
- खेत का नाम: {farm_name}
- स्थान: {village}, {district}, {state}
- भू-भाग: {terrain} | मिट्टी का प्रकार: {soil_type} | सिंचाई व्यवस्था: {irrigation}
- वर्तमान फसल: {crop} | फसल की अवस्था: {crop_stage}
- वर्तमान मौसम: तापमान {current_temp}°C, मौसम स्थिति: {current_condition}, सापेक्ष आर्द्रता {current_humidity}%, हवा की गति {current_wind} km/h
- अगले 1-3 दिन का तात्कालिक जोखिम (Horizon 1): {horizon_1_risks}
- 30-दिवसीय वर्षा मौसमी रुझान (Horizon 3): {seasonal_outlook}
- ईएनएसओ (ENSO) स्थिति: {enso_phase} ({enso_status})

【भारतीय मौसम आपदाएं व वैज्ञानिक सुरक्षा उपाय (Agro-Climatic Knowledge Base)】:
1. पाला व शीत लहर (Frost / Cold Wave): 0°C - 4°C तापमान। उपाय: शाम को खेत में हल्की सिंचाई (मिट्टी का तापमान 1-2°C बढ़ता है), उत्तर-पश्चिम मेड़ों पर धुआं (Smoke screen), नर्सरी को पुआल/पॉलीथीन से ढकना, 0.1% घुलनशील गंधक का छिड़काव।
2. लू व भीषण गर्मी (Heatwave): 40°C - 47°C तापमान। उपाय: शाम या रात में स्प्रिंकलर/ड्रिप से हल्की सिंचाई, पुआल की मल्चिंग (वाष्पीकरण रोकना), केओलिन (Kaolin clay 5%) एंटी-ट्रांसपिरेंट छिड़काव, फूलों व परागकणों की सुरक्षा।
3. अतिवृष्टि, जलभराव व बाढ़ (Heavy Rain / Waterlogging): 64.5mm से अधिक वर्षा। उपाय: कूंड़-मेड़ (Ridge and Furrow) व जल निकासी नालियां खोलना, खड़े पानी को 24-48 घंटे में निकालना, यूरिया की टॉप ड्रेसिंग तुरंत रोकना, पानी निकलने पर 1% यूरिया या 19:19:19 का पर्णीय छिड़काव।
4. सूखा व वर्षा की लंबी खेंच (Dry Spells / Drought): जीवनरक्षक सिंचाई (क्राउन रूट, फूल, फली भराव अवस्था), धूल मल्चिंग (Dust mulch - उथली निराई), एंटी-ट्रांसपिरेंट, सूखा-सहनशील किस्में (बाजरा, मूंग, मोठ, ग्वार), खेत तलाई (Farm pond) से सूक्ष्म सिंचाई।
5. ओलावृष्टि, आंधी व वज्रपात (Hailstorm & Thunderstorm): फलदार बागों में एंटी-हेल नेट, मक्का/गन्ना/केला में मिट्टी चढ़ाना (Earthing up), 72 घंटे में PMFBY (14447) पर नुकसान दर्ज करना।
6. तेज चक्रवाती हवाएं (Cyclones / High Winds): बागवानी में डंडों का सहारा (Staking), पकी फसल की तत्काल कटाई, जल निकासी।

【ऋतु, फसल, मिट्टी व भू-भाग ज्ञान (Seasons, Crops, Soils & Terrains)】:
- खरीफ (जून-अक्तूबर): धान, सोयाबीन, कपास, मक्का, बाजरा, अरहर, मूंगफली। मॉनसून प्रबंधन, जल निकासी, कीट निगरानी।
- रबी (अक्तूबर-मार्च): गेहूं (CRI अवस्था 21 दिन पर पहली सिंचाई), सरसों (माहू कीट व पाले से बचाव), चना (फूल पर सिंचाई न करें, T-खूंटियां), आलू, मटर।
- जायद (मार्च-जून): मूंग, उड़द, तरबूज, ककड़ी, चारा। उच्च वाष्पीकरण, लू सुरक्षा, ड्रिप सिंचाई।
- मिट्टी प्रकार: काली मिट्टी (उच्च नमी धारण, जलभराव का डर - अधिक पानी न दें), जलोढ़ मिट्टी (उपजाऊ, संतुलित NPK), लाल मिट्टी (कम नमी - बार-बार हल्की सिंचाई), बलुई मिट्टी (ड्रिप व मल्चिंग अनिवार्य), दोमट मिट्टी (आदर्श जल-वायु संचार)।
- भू-भाग: मैदानी (जल निकासी प्रबंध), पहाड़ी (सीढ़ीदार खेती, कंटूर मेड़बंदी, मृदा अपरदन रोकथाम), पठारी (वर्षा जल संचयन), तटीय (लवण सहनशील किस्में), शुष्क (ड्रिप व बाजरा)।

【अनिवार्य नियम व सुरक्षा दिशानिर्देश (Strict Guardrails)】:
1. संक्षिप्तता (Brevity): उत्तर अत्यंत संक्षिप्त, सीधा और टू-द-पॉइंट दें — अधिकतम 2 छोटे वाक्य (35 शब्दों के भीतर)। लंबी भूमिका या पैराग्राफ बिल्कुल न लिखें।
2. भाषा: केवल सरल व स्पष्ट हिंदी।
3. मौसम संख्याएं कभी मन से न बनाएं: केवल ऊपर दिए गए Grounding Data ({current_temp}°C, {village}) का उल्लेख करें।
4. रासायनिक खुराक न दें; जैविक उपाय (नीम तेल, ट्राइकोडर्मा) बताएं और रासायनिक मात्रा हेतु KVK टोल-फ्री 1800-180-1551 बताएं।
"""

class AIAdvisorService:
    def __init__(self):
        self.api_key = os.environ.get("GEMINI_API_KEY") or settings.GEMINI_API_KEY
        self.model = "gemini-3.5-flash-lite"
        self.base_url = "https://generativelanguage.googleapis.com/v1beta/models"

    def _build_grounded_prompt(
        self,
        farm_profile: Dict[str, Any],
        weather_data: Dict[str, Any],
        risk_data: Dict[str, Any],
        enso_data: Dict[str, Any]
    ) -> str:
        current = weather_data.get("current", {})
        h1_risks = risk_data.get("horizon_1_3d", {}).get("risks_detected", [])
        h1_str = ", ".join([f"{r.get('title_hi')} ({r.get('probability')}%)" for r in h1_risks]) or "कोई गंभीर तात्कालिक जोखिम नहीं"
        
        h3_risks = risk_data.get("horizon_10_46d_seasonal", {}).get("risks_detected", [])
        h3_str = h3_risks[0].get("accuracy_compliant_statement_hi") if h3_risks else "सामान्य वर्षा की संभावना"

        return SYSTEM_PROMPT_TEMPLATE.format(
            farm_name=farm_profile.get("name", "मेरा खेत"),
            village=farm_profile.get("village", "आपका क्षेत्र"),
            district=farm_profile.get("district", "स्थानीय क्षेत्र"),
            state=farm_profile.get("state", "India"),
            terrain=farm_profile.get("terrain", "plain"),
            soil_type=farm_profile.get("soil_type", "black"),
            irrigation=farm_profile.get("irrigation_type", "tube-well"),
            crop=farm_profile.get("current_crop", "सोयाबीन"),
            crop_stage=farm_profile.get("crop_stage", "फूल आने की अवस्था"),
            current_temp=current.get("temperature", 24.0),
            current_condition=current.get("condition", "साफ मौसम"),
            current_humidity=current.get("relative_humidity", 50.0),
            current_wind=current.get("wind_speed", 5.0),
            horizon_1_risks=h1_str,
            seasonal_outlook=h3_str,
            enso_phase=enso_data.get("phase_hi", "तटस्थ (Neutral)"),
            enso_status=enso_data.get("status_hi", "सामान्य स्थिति")
        )

    async def get_farming_advice(
        self,
        user_message: str,
        farm_profile: Dict[str, Any],
        weather_data: Dict[str, Any],
        risk_data: Dict[str, Any],
        enso_data: Dict[str, Any],
        client_api_key: Optional[str] = None,
    ) -> Dict[str, Any]:
        system_instruction = self._build_grounded_prompt(farm_profile, weather_data, risk_data, enso_data)

        # 1. Real Gemini API Call if key is set via client request, .env, or env variable
        effective_key = client_api_key or self.api_key or os.environ.get("GEMINI_API_KEY") or settings.GEMINI_API_KEY
        if effective_key and str(effective_key).strip() and str(effective_key).strip() != "mock_key":
            clean_key = str(effective_key).strip()
            models_to_try = [self.model, "gemini-3.8-flash", "gemini-flash-latest"]
            for m in models_to_try:
                try:
                    url = f"{self.base_url}/{m}:generateContent?key={clean_key}"
                    payload = {
                        "contents": [
                            {
                                "role": "user",
                                "parts": [{"text": user_message}]
                            }
                        ],
                        "systemInstruction": {
                            "parts": [{"text": system_instruction}]
                        },
                        "generationConfig": {
                            "temperature": 0.2,
                            "maxOutputTokens": 160
                        }
                    }
                    async with httpx.AsyncClient(timeout=15.0) as client:
                        resp = await client.post(url, json=payload)
                        if resp.status_code == 200:
                            data = resp.json()
                            candidates = data.get("candidates", [])
                            if candidates:
                                reply_text = candidates[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                                if reply_text and len(reply_text.strip()) > 0:
                                    return self._format_response(reply_text, farm_profile)
                        else:
                            logger.warning(f"Gemini API model {m} returned status {resp.status_code}: {resp.text}")
                except Exception as e:
                    logger.error(f"Gemini API error for model {m}: {e}. Trying next model if available.")

        # 2. Resilient Grounded Intelligent Fallback (ICAR Rule-Engine Based)
        return self._generate_grounded_fallback_advice(
            user_message, farm_profile, weather_data, risk_data, enso_data
        )

    def _generate_grounded_fallback_advice(
        self,
        user_message: str,
        farm_profile: Dict[str, Any],
        weather_data: Dict[str, Any],
        risk_data: Dict[str, Any],
        enso_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        crop = farm_profile.get("current_crop", "सोयाबीन")
        stage = farm_profile.get("crop_stage", "फूल आने की अवस्था")
        village = farm_profile.get("village", "आपका क्षेत्र")
        district = farm_profile.get("district", village)
        soil = farm_profile.get("soil_type", "black")
        terrain = farm_profile.get("terrain", "plain")

        current = weather_data.get("current", {})
        current_temp = current.get("temperature", 24.0)
        current_humidity = current.get("relative_humidity", 50.0)
        current_wind = current.get("wind_speed", 5.0)
        condition = current.get("condition") or ("साफ मौसम" if current_temp > 20 else "ठंडा मौसम")

        daily = weather_data.get("daily", [])
        today_rain = daily[0].get("precipitation_sum", 0.0) if daily else 0.0
        today_rain_prob = daily[0].get("precipitation_probability_max", 0.0) if daily else 0.0

        # Horizon 1 & Horizon 3 summary
        h1_risks = risk_data.get("horizon_1_3d", {}).get("risks_detected", [])
        h1_names = [r.get("title_hi") for r in h1_risks if r.get("title_hi")]
        enso_phase = enso_data.get("phase_hi", "तटस्थ")

        msg_lower = user_message.lower().strip()

        # Soil Hindi Mapping
        soil_names = {
            "black": "काली मिट्टी (Black Soil)",
            "alluvial": "जलोढ़ मिट्टी (Alluvial Soil)",
            "red": "लाल व पीली मिट्टी (Red Soil)",
            "sandy": "बलुई / रेतीली मिट्टी (Sandy Soil)",
            "loamy": "दोमट मिट्टी (Loamy Soil)",
        }
        soil_hi = soil_names.get(soil, "सामान्य मिट्टी")

        import re

        if any(w in msg_lower for w in ["temperature", "temp", "तापमान", "मौसम कैसा", "weather", "aaj ka mausam", "हाल", "आर्द्रता", "humidity", "हवा", "कितना तापमान", "कितना डिग्री", "kitna temp", "kitna h", "kitna hai"]):
            reply = f"{village} में अभी तापमान {current_temp}°C ({condition}, हवा {current_wind} km/h, नमी {current_humidity}%) है। {crop} में शाम के समय हल्की नमी बनाए रखें।"
            tips = [f"तापमान: {current_temp}°C ({condition})", "तेज धूप में छिड़काव न करें"]

        elif any(w in msg_lower for w in ["नमस्ते", "नमस्कार", "राम-राम", "राम राम", "राधे राधे", "kaise ho", "कैसे हो", "कौन हो", "who are you", "kya kar sakte", "क्या कर सकते"]) or re.search(r'\b(hi|hello|hey)\b', msg_lower):
            reply = f"राम-राम! {village} में अभी {current_temp}°C ({condition}) है। {crop}, सिंचाई या मौसम सुरक्षा पर सीधा सवाल पूछें।"
            tips = [f"वर्तमान तापमान: {current_temp}°C", "KVK हेल्पलाइन: 1800-180-1551"]

        elif any(w in msg_lower for w in ["बारिश", "बरसात", "वर्षा", "rain", "precipitation", "पानी गिरेगा", "पानी पड़ेगा", "बरसेगा", "kab hogi", "होगी क्या"]):
            if today_rain_prob >= 35.0 or today_rain > 2.0:
                reply = f"आज {village} में बारिश की {today_rain_prob}% संभावना ({today_rain} मिमी) है। सिंचाई व स्प्रे रोकें और नालियां साफ रखें।"
            else:
                reply = f"आज {village} में बारिश की संभावना कम ({today_rain_prob}%) है। मिट्टी सूखी हो तो शाम को हल्की सिंचाई करें।"
            tips = [f"वर्षा संभावना: {today_rain_prob}%", "खेत की नालियां साफ रखें"]

        elif any(w in msg_lower for w in ["हवा", "आंधी", "wind", "तूफान"]):
            wind_advice = "छिड़काव सुरक्षित है।" if current_wind < 15.0 else "तेज हवा में स्प्रे न करें।"
            reply = f"{village} में हवा की गति {current_wind} km/h है; {wind_advice}"
            tips = [f"हवा: {current_wind} km/h", "15 km/h से तेज हवा में स्प्रे न करें"]

        elif any(w in msg_lower for w in ["जलभराव", "बाढ़", "भारी बारिश", "पानी भर", "flood", "अतिवृष्टि"]):
            reply = f"खेत से 24 घंटे के भीतर खड़ा पानी निकालें और यूरिया छिड़काव रोकें। पानी उतरने पर जैविक ट्राइकोडर्मा का प्रयोग करें।"
            tips = ["तुरंत जल निकासी करें", "जलभराव में यूरिया न डालें"]

        elif any(w in msg_lower for w in ["पाला", "पाले", "पाल", "ठंड", "शीत", "frost", "cold", "सर्द", "कोहरा"]):
            reply = f"पाले (0-4°C) से {crop} को बचाने हेतु शाम को हल्की सिंचाई करें और मेड़ पर धुआं या 0.1% घुलनशील गंधक का स्प्रे करें।"
            tips = ["शाम को हल्की सिंचाई करें", "0.1% घुलनशील गंधक स्प्रे"]

        elif any(w in msg_lower for w in ["लू", "गर्मी", "heat", "गर्म"]):
            reply = f"लू (>40°C) से बचाव हेतु केवल शाम 5 बजे बाद सिंचाई करें और नमी बचाने के लिए पुआल की मल्चिंग बिछाएं।"
            tips = ["शाम 5 बजे बाद सिंचाई करें", "पुआल की मल्चिंग करें"]

        elif any(w in msg_lower for w in ["सूखा", "कम बारिश", "drought", "एल नीनो", "el nino", "मौसम रुझान", "30 दिन"]):
            reply = f"सूखे में {crop} को केवल फूल व फली बनने की क्रांतिक अवस्था पर ड्रिप से पानी दें और उथली गुड़ाई (धूल मल्चिंग) करें।"
            tips = ["क्रांतिक अवस्था पर ड्रिप सिंचाई करें", "उथली गुड़ाई कर नमी बचाएं"]

        elif any(w in msg_lower for w in ["कीट", "दवा", "कीटनाशक", "खाद", "रोग", "बीमारी", "pest", "spray", "इल्ली", "सुंडी", "माहू"]):
            reply = f"{crop} में कीट नियंत्रण हेतु नीम तेल (5 मिली/लीटर) का स्प्रे करें और 5-6 पीले ट्रैप लगाएं। रासायनिक खुराक हेतु KVK 1800-180-1551 पर पूछें।"
            tips = ["नीम तेल 5ml/L स्प्रे करें", "KVK हेल्पलाइन: 1800-180-1551"]

        elif any(w in msg_lower for w in ["गेहूं", "wheat"]):
            reply = f"गेहूं में बुवाई के 21 दिन पर (CRI अवस्था) पहली हल्की सिंचाई करें। पाले से बचाव हेतु शाम को नमी बनाए रखें।"
            tips = ["21 दिन पर पहली सिंचाई दें", "पीला रतुआ की निगरानी रखें"]
        elif any(w in msg_lower for w in ["सरसों", "mustard"]):
            reply = f"सरसों में फूल खिलते समय गहरी सिंचाई न करें। माहू कीट के लिए 4-5 पीले स्टिकी ट्रैप लगाएं।"
            tips = ["फूल पर गहरी सिंचाई न करें", "माहू हेतु पीले ट्रैप लगाएं"]
        elif any(w in msg_lower for w in ["धान", "rice", "paddy"]):
            reply = f"धान में कल्ले फूटते समय 2-4 सेमी पानी रखें और तना छेदक हेतु फेरोमोन ट्रैप लगाएं।"
            tips = ["2-4 सेमी पानी बनाए रखें", "फेरोमोन ट्रैप लगाएं"]
        elif any(w in msg_lower for w in ["कपास", "cotton"]):
            reply = f"कपास में जलभराव बिल्कुल न होने दें और गुलाबी सुंडी की रोकथाम हेतु फेरोमोन ट्रैप व नीम तेल अपनाएं।"
            tips = ["जल निकासी साफ रखें", "फेरोमोन ट्रैप लगाएं"]
        elif any(w in msg_lower for w in ["चना", "gram", "chickpea"]):
            reply = f"चने में फूल आते समय सिंचाई बिल्कुल न करें। फली छेदक कीट हेतु खेत में T-खूंटियां लगाएं और नीम तेल स्प्रे करें।"
            tips = ["फूल आने पर सिंचाई न करें", "खेत में T-खूंटियां लगाएं"]
        elif any(w in msg_lower for w in ["आलू", "potato"]):
            reply = f"आलू को पाले से बचाने हेतु शाम को हल्की सिंचाई करें और कंद ढकने के लिए समय पर मिट्टी चढ़ाएं।"
            tips = ["शाम को हल्की सिंचाई करें", "झुलसा रोग की निगरानी करें"]

        elif any(w in msg_lower for w in ["बीमा", "pmfby", "मुआवजा", "दावा", "insurance"]):
            reply = f"प्राकृतिक आपदा के 72 घंटे के भीतर PMFBY टोल-फ्री 14447 या क्रॉप इंश्योरेंस ऐप पर फोटो सहित दावा दर्ज करें।"
            tips = ["72 घंटे में 14447 पर कॉल करें", "ऐप पर फोटो अपलोड करें"]

        elif any(w in msg_lower for w in ["पानी", "सिंचाई", "water", "irrigation", "नमी"]):
            reply = f"2-3 इंच गहराई पर मिट्टी की नमी जांचें; सूखी होने पर केवल शाम को हल्की सिंचाई करें और पुआल की मल्चिंग करें।"
            tips = ["शाम को हल्की सिंचाई करें", "2-3 इंच गहराई पर नमी जांचें"]

        else:
            reply = f"{village} में अभी {current_temp}°C ({condition}) है। {crop} ({stage}) में नमी जांचकर शाम को हल्की सिंचाई करें व कीटों हेतु नीम तेल अपनाएं।"
            tips = ["नियमित नमी जांचें", "KVK हेल्पलाइन: 1800-180-1551"]

        return self._format_response(reply, farm_profile, tips)

    def _format_response(
        self,
        reply_text: str,
        farm_profile: Dict[str, Any],
        tips: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        return {
            "reply_text": reply_text,
            "actionable_tips": tips or [
                "मौसम देखकर ही सिंचाई व स्प्रे करें",
                "KVK हेल्पलाइन: 1800-180-1551"
            ],
            "kvk_contact": "1800-180-1551",
            "disclaimer": "ICAR/IMD मानक सलाह। रासायनिक मात्रा हेतु KVK 1800-180-1551 पर पूछें।",
            "grounding_summary": {
                "farm": farm_profile.get("name"),
                "village": farm_profile.get("village"),
                "crop": farm_profile.get("current_crop"),
                "stage": farm_profile.get("crop_stage"),
                "soil": farm_profile.get("soil_type")
            }
        }

ai_advisor_service = AIAdvisorService()
