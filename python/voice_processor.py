#!/usr/bin/env python3
"""
Voice-to-Terrain Generation Processor
Handles: Audio file -> OpenAI Whisper (STT) -> GPT analysis -> Terrain parameters (JSON)

Usage: python voice_processor.py <audio_file_path>
Output: JSON with terrain parameters
"""

import sys
import json
import os
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# OpenAI imports
try:
    import openai
    from openai import OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False
    print("Warning: OpenAI library not installed. Install with: pip install openai")

# Audio processing imports
try:
    import whisper
    WHISPER_AVAILABLE = True
except ImportError:
    WHISPER_AVAILABLE = False
    print("Warning: Whisper library not installed. Install with: pip install openai-whisper")

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class VoiceTerrainProcessor:
    def __init__(self):
        self.openai_client = None
        self.whisper_model = None
        self.setup_openai()
        self.setup_whisper()
        
        # Terrain generation context for GPT
        self.terrain_context = """
        You are a terrain generation assistant for a VR application. Your task is to convert natural language descriptions of terrain into specific parameter values for procedural generation.

        Available terrain types:
        - FLAT (0): Minimal variation, plains
        - HILLS (1): Rolling hills, moderate elevation changes  
        - MOUNTAINS (2): High peaks, dramatic elevation
        - VALLEYS (3): Low areas, depressions
        - PLATEAU (4): Flat-topped elevated areas
        - CUSTOM (5): Mixed features

        Parameters to output:
        - seed: Random integer (0-10000)
        - frequency: Controls feature size (0.01-1.0, lower = larger features)
        - amplitude: Height variation (0.5-20.0)
        - octaves: Detail layers (1-6)
        - lacunarity: Frequency multiplier per octave (1.5-3.0)
        - persistence: Amplitude multiplier per octave (0.1-0.8)
        - terrain_type: Integer 0-5 corresponding to types above
        - erosion: Water erosion effect (0.0-1.0)
        - plateau: Plateau threshold (0.0-15.0)

        Examples:
        "I want rolling hills" -> {"terrain_type": 1, "amplitude": 8.0, "frequency": 0.1}
        "Make some mountains with rivers" -> {"terrain_type": 2, "amplitude": 15.0, "erosion": 0.3}
        "Flat area with small bumps" -> {"terrain_type": 0, "amplitude": 2.0, "octaves": 2}
        """

    def setup_openai(self):
        """Initialize OpenAI client with API key"""
        if not OPENAI_AVAILABLE:
            logger.warning("OpenAI not available, using fallback mode")
            return
            
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            logger.warning("OPENAI_API_KEY not found in environment variables")
            # Look for API key file in project directory
            api_key_file = Path(__file__).parent / "openai_key.txt"
            if api_key_file.exists():
                api_key = api_key_file.read_text().strip()
                logger.info("Loaded OpenAI API key from file")
            else:
                logger.warning("No OpenAI API key found, using fallback mode")
                return
        
        try:
            self.openai_client = OpenAI(api_key=api_key)
            logger.info("OpenAI client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize OpenAI client: {e}")

    def setup_whisper(self):
        """Initialize Whisper model for speech-to-text"""
        if not WHISPER_AVAILABLE:
            logger.warning("Whisper not available, using fallback mode")
            return
            
        try:
            # Use small model for faster processing
            self.whisper_model = whisper.load_model("base")
            logger.info("Whisper model loaded successfully")
        except Exception as e:
            logger.error(f"Failed to load Whisper model: {e}")

    def transcribe_audio(self, audio_file_path: str) -> Optional[str]:
        """Convert audio file to text using Whisper"""
        if not self.whisper_model:
            return self.fallback_transcription(audio_file_path)
            
        try:
            logger.info(f"Transcribing audio file: {audio_file_path}")
            result = self.whisper_model.transcribe(audio_file_path)
            text = result["text"].strip()
            logger.info(f"Transcription successful: '{text}'")
            return text
        except Exception as e:
            logger.error(f"Whisper transcription failed: {e}")
            return self.fallback_transcription(audio_file_path)

    def fallback_transcription(self, audio_file_path: str) -> str:
        """Fallback transcription for testing without Whisper"""
        filename = Path(audio_file_path).stem.lower()
        
        # Simple pattern matching based on common test phrases
        fallback_phrases = {
            "mountain": "I want some mountains",
            "hill": "Make rolling hills", 
            "valley": "Create valleys with a river",
            "flat": "I want a flat plain",
            "rough": "Make rough rocky terrain",
            "smooth": "Create smooth gentle hills"
        }
        
        for keyword, phrase in fallback_phrases.items():
            if keyword in filename:
                logger.info(f"Using fallback transcription: '{phrase}'")
                return phrase
        
        # Default fallback
        default_phrase = "Create hilly terrain"
        logger.info(f"Using default fallback transcription: '{default_phrase}'")
        return default_phrase

    def analyze_terrain_request(self, text: str) -> Dict:
        """Convert natural language to terrain parameters using GPT"""
        if not self.openai_client:
            return self.fallback_analysis(text)
            
        try:
            logger.info(f"Analyzing terrain request: '{text}'")
            
            prompt = f"""
            {self.terrain_context}
            
            User request: "{text}"
            
            Respond with ONLY a JSON object containing the terrain parameters. No explanation.
            """
            
            response = self.openai_client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are a terrain parameter generator. Respond only with valid JSON."},
                    {"role": "user", "content": prompt}
                ],
                max_tokens=200,
                temperature=0.3
            )
            
            response_text = response.choices[0].message.content.strip()
            logger.info(f"GPT response: {response_text}")
            
            # Parse the JSON response
            parameters = json.loads(response_text)
            return self.validate_parameters(parameters)
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse GPT response as JSON: {e}")
            return self.fallback_analysis(text)
        except Exception as e:
            logger.error(f"GPT analysis failed: {e}")
            return self.fallback_analysis(text)

    def fallback_analysis(self, text: str) -> Dict:
        """Fallback analysis using keyword matching"""
        logger.info("Using fallback keyword analysis")
        text_lower = text.lower()
        
        # Default parameters
        params = {
            "seed": int.from_bytes(os.urandom(4), byteorder='big') % 10000,
            "frequency": 0.1,
            "amplitude": 5.0,
            "octaves": 3,
            "lacunarity": 2.0,
            "persistence": 0.5,
            "terrain_type": 1,  # HILLS
            "erosion": 0.0,
            "plateau": 0.0
        }
        
        # Terrain type keywords
        if any(word in text_lower for word in ["mountain", "mountains", "peak", "peaks"]):
            params.update({
                "terrain_type": 2,  # MOUNTAINS
                "amplitude": 15.0,
                "frequency": 0.05
            })
        elif any(word in text_lower for word in ["hill", "hills", "hilly", "rolling"]):
            params.update({
                "terrain_type": 1,  # HILLS
                "amplitude": 8.0,
                "frequency": 0.1
            })
        elif any(word in text_lower for word in ["valley", "valleys", "depression", "low"]):
            params.update({
                "terrain_type": 3,  # VALLEYS
                "amplitude": 6.0
            })
        elif any(word in text_lower for word in ["flat", "plain", "plains", "level"]):
            params.update({
                "terrain_type": 0,  # FLAT
                "amplitude": 1.0
            })
        elif any(word in text_lower for word in ["plateau", "mesa", "tableland"]):
            params.update({
                "terrain_type": 4,  # PLATEAU
                "plateau": 5.0,
                "amplitude": 8.0
            })
        
        # Size modifiers
        if any(word in text_lower for word in ["large", "big", "huge", "massive"]):
            params["frequency"] *= 0.5
            params["amplitude"] *= 1.5
        elif any(word in text_lower for word in ["small", "tiny", "little", "mini"]):
            params["frequency"] *= 2.0
            params["amplitude"] *= 0.7
        
        # Detail modifiers
        if any(word in text_lower for word in ["rough", "jagged", "rocky", "detailed"]):
            params["octaves"] = 5
            params["lacunarity"] = 2.5
        elif any(word in text_lower for word in ["smooth", "gentle", "soft", "simple"]):
            params["octaves"] = 2
            params["persistence"] = 0.3
        
        # Water features
        if any(word in text_lower for word in ["river", "stream", "water", "creek"]):
            params["erosion"] = 0.3
        
        logger.info(f"Fallback analysis result: {params}")
        return params

    def validate_parameters(self, params: Dict) -> Dict:
        """Validate and clamp terrain parameters to safe ranges"""
        # Define parameter constraints
        constraints = {
            "seed": (0, 10000),
            "frequency": (0.01, 1.0),
            "amplitude": (0.5, 20.0),
            "octaves": (1, 6),
            "lacunarity": (1.5, 3.0),
            "persistence": (0.1, 0.8),
            "terrain_type": (0, 5),
            "erosion": (0.0, 1.0),
            "plateau": (0.0, 15.0)
        }
        
        validated = {}
        for key, (min_val, max_val) in constraints.items():
            if key in params:
                value = params[key]
                if isinstance(value, (int, float)):
                    validated[key] = max(min_val, min(max_val, value))
                else:
                    logger.warning(f"Invalid type for {key}: {type(value)}")
                    validated[key] = min_val
            else:
                # Set default values for missing parameters
                defaults = {
                    "seed": 42,
                    "frequency": 0.1,
                    "amplitude": 5.0,
                    "octaves": 3,
                    "lacunarity": 2.0,
                    "persistence": 0.5,
                    "terrain_type": 1,
                    "erosion": 0.0,
                    "plateau": 0.0
                }
                validated[key] = defaults[key]
        
        # Ensure terrain_type is integer
        validated["terrain_type"] = int(validated["terrain_type"])
        validated["seed"] = int(validated["seed"])
        validated["octaves"] = int(validated["octaves"])
        
        logger.info(f"Validated parameters: {validated}")
        return validated

    def process_voice_command(self, audio_file_path: str) -> Dict:
        """Complete pipeline: audio -> text -> parameters"""
        if not os.path.exists(audio_file_path):
            return {"error": f"Audio file not found: {audio_file_path}"}
        
        # Step 1: Transcribe audio to text
        text = self.transcribe_audio(audio_file_path)
        if not text:
            return {"error": "Failed to transcribe audio"}
        
        # Step 2: Analyze text for terrain parameters
        parameters = self.analyze_terrain_request(text)
        
        # Step 3: Return complete result
        result = {
            "text": text,
            "parameters": parameters,
            "keywords": self.extract_keywords(text),
            "success": True
        }
        
        logger.info(f"Voice processing complete: {result}")
        return result

    def extract_keywords(self, text: str) -> List[str]:
        """Extract terrain-relevant keywords from text"""
        keywords = []
        text_lower = text.lower()
        
        # Terrain type keywords
        terrain_keywords = [
            "mountain", "mountains", "hill", "hills", "valley", "valleys",
            "flat", "plain", "plains", "plateau", "mesa"
        ]
        
        # Feature keywords
        feature_keywords = [
            "river", "stream", "water", "rough", "smooth", "jagged", 
            "gentle", "steep", "rocky", "grassy", "forest"
        ]
        
        # Size keywords
        size_keywords = [
            "large", "big", "huge", "small", "tiny", "massive", "mini"
        ]
        
        all_keywords = terrain_keywords + feature_keywords + size_keywords
        
        for keyword in all_keywords:
            if keyword in text_lower:
                keywords.append(keyword)
        
        return keywords

def main():
    """Main entry point for the script"""
    if len(sys.argv) != 2:
        print(json.dumps({"error": "Usage: python voice_processor.py <audio_file_path>"}))
        return
    
    audio_file_path = sys.argv[1]
    
    try:
        processor = VoiceTerrainProcessor()
        result = processor.process_voice_command(audio_file_path)
        print(json.dumps(result, indent=2))
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()