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
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Ensure ffmpeg is on PATH - Godot's OS.execute may not inherit the full system PATH
if not shutil.which("ffmpeg"):
    _ffmpeg_paths = [
        r"C:\Apps\ffmpeg-master-latest-win64-gpl\bin",
        r"C:\ffmpeg\bin",
        os.path.expanduser(r"~\ffmpeg\bin"),
    ]
    for _p in _ffmpeg_paths:
        if os.path.isfile(os.path.join(_p, "ffmpeg.exe")):
            os.environ["PATH"] = _p + os.pathsep + os.environ.get("PATH", "")
            break

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

# Setup logging - write to file next to this script for pipeline debugging
_log_file = Path(__file__).parent / "voice_processor.log"
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(_log_file, mode="w"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class VoiceTerrainProcessor:
    def __init__(self, project_dir: str = None):
        self.openai_client = None
        self.whisper_model = None
        self.project_dir = Path(project_dir) if project_dir else Path(__file__).parent
        self.setup_openai()
        self.setup_whisper()
        
        # Terrain generation context for GPT
        # NOTE: Terrain chunks are 8-32 meters wide in VR. Amplitude is peak height in meters.
        # Values must be small to look natural at VR scale (viewer is ~1.7m tall).
        self.terrain_context = """
        You are a terrain generation assistant for a VR application. Terrain chunks are 8-32 meters wide and the viewer is human-scale (1.7m tall). Amplitude is peak height in METERS - keep values low for natural-looking VR terrain.

        Available terrain types:
        - FLAT (0): Nearly level ground. amplitude: 0.1-0.3
        - HILLS (1): Gentle rolling hills. amplitude: 0.8-2.0
        - MOUNTAINS (2): Dramatic peaks. amplitude: 2.5-4.0
        - VALLEYS (3): Depressions and low areas. amplitude: 1.0-2.0
        - PLATEAU (4): Flat-topped elevated terrain. amplitude: 1.5-3.0, plateau must be LESS than amplitude (plateau is the height above which terrain is flattened)
        - CUSTOM (5): Mixed features. amplitude: 0.5-3.0

        Parameters to output (all required):
        - seed: Random integer (0-10000)
        - frequency: Feature size (0.01-0.5). Lower = larger features. Typical: 0.05-0.15
        - amplitude: Peak height in meters (0.1-4.0). IMPORTANT: keep within terrain type ranges above
        - octaves: Detail layers (1-5). Flat: 1, hills: 2-3, mountains: 3-5
        - lacunarity: Frequency multiplier per octave (1.5-2.5)
        - persistence: Amplitude multiplier per octave (0.2-0.6)
        - terrain_type: Integer 0-5 corresponding to types above
        - erosion: Water erosion effect (0.0-1.0). Only use > 0 if water/rivers mentioned
        - plateau: Flattening threshold in meters (0.0-3.0). Only for terrain_type 4. Must be less than amplitude.

        Examples:
        "I want rolling hills" -> {"seed": 1234, "terrain_type": 1, "amplitude": 1.5, "frequency": 0.1, "octaves": 3, "lacunarity": 2.0, "persistence": 0.4, "erosion": 0.0, "plateau": 0.0}
        "Make some mountains" -> {"seed": 5678, "terrain_type": 2, "amplitude": 3.5, "frequency": 0.06, "octaves": 4, "lacunarity": 2.2, "persistence": 0.5, "erosion": 0.0, "plateau": 0.0}
        "Flat area" -> {"seed": 9012, "terrain_type": 0, "amplitude": 0.2, "frequency": 0.1, "octaves": 1, "lacunarity": 2.0, "persistence": 0.3, "erosion": 0.0, "plateau": 0.0}
        "A plateau" -> {"seed": 3456, "terrain_type": 4, "amplitude": 2.5, "frequency": 0.07, "octaves": 3, "lacunarity": 2.0, "persistence": 0.4, "erosion": 0.0, "plateau": 1.0}
        "Mountains with a river" -> {"seed": 7890, "terrain_type": 2, "amplitude": 3.0, "frequency": 0.05, "octaves": 4, "lacunarity": 2.0, "persistence": 0.5, "erosion": 0.3, "plateau": 0.0}
        """

    def setup_openai(self):
        """Initialize OpenAI client with API key"""
        if not OPENAI_AVAILABLE:
            logger.warning("OpenAI not available, using fallback mode")
            return
            
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            logger.warning("OPENAI_API_KEY not found in environment variables")
            # Look for API key file in project directory and python subfolder
            api_key_file = self.project_dir / "python" / "openai_key.txt"
            if not api_key_file.exists():
                api_key_file = self.project_dir / "openai_key.txt"
            if not api_key_file.exists():
                api_key_file = Path(__file__).parent / "openai_key.txt"
            if api_key_file.exists():
                api_key = api_key_file.read_text().strip()
                logger.info(f"Loaded OpenAI API key from: {api_key_file}")
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
            result = self.whisper_model.transcribe(audio_file_path, fp16=False)
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

        # Default parameters - VR scale (chunks are 8-32m, viewer is 1.7m tall)
        params = {
            "seed": int.from_bytes(os.urandom(4), byteorder='big') % 10000,
            "frequency": 0.1,
            "amplitude": 1.5,
            "octaves": 3,
            "lacunarity": 2.0,
            "persistence": 0.4,
            "terrain_type": 1,  # HILLS
            "erosion": 0.0,
            "plateau": 0.0
        }

        # Terrain type keywords
        if any(word in text_lower for word in ["mountain", "mountains", "peak", "peaks"]):
            params.update({
                "terrain_type": 2,  # MOUNTAINS
                "amplitude": 3.5,
                "frequency": 0.06,
                "octaves": 4,
                "persistence": 0.5
            })
        elif any(word in text_lower for word in ["hill", "hills", "hilly", "rolling"]):
            params.update({
                "terrain_type": 1,  # HILLS
                "amplitude": 1.5,
                "frequency": 0.1,
                "persistence": 0.5,
                "octaves": 3
            })
        elif any(word in text_lower for word in ["valley", "valleys", "depression", "low"]):
            params.update({
                "terrain_type": 3,  # VALLEYS
                "amplitude": 1.5
            })
        elif any(word in text_lower for word in ["flat", "plain", "plains", "level"]):
            params.update({
                "terrain_type": 0,  # FLAT
                "amplitude": 0.2,
                "octaves": 1
            })
        elif any(word in text_lower for word in ["plateau", "mesa", "tableland"]):
            params.update({
                "terrain_type": 4,  # PLATEAU
                "plateau": 1.0,
                "amplitude": 2.5
            })

        # Size modifiers
        if any(word in text_lower for word in ["large", "big", "huge", "massive"]):
            params["frequency"] *= 0.5
            params["amplitude"] *= 1.3
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
        # Define parameter constraints - VR scale (8-32m chunks, 1.7m viewer)
        constraints = {
            "seed": (0, 10000),
            "frequency": (0.01, 0.5),
            "amplitude": (0.1, 4.0),
            "octaves": (1, 5),
            "lacunarity": (1.5, 2.5),
            "persistence": (0.1, 0.6),
            "terrain_type": (0, 5),
            "erosion": (0.0, 1.0),
            "plateau": (0.0, 3.0)
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
                    "amplitude": 1.5,
                    "octaves": 3,
                    "lacunarity": 2.0,
                    "persistence": 0.4,
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
    # Parse arguments: voice_processor.py <audio_file> [--project-dir <path>]
    args = sys.argv[1:]
    project_dir = None
    audio_file_path = None

    i = 0
    while i < len(args):
        if args[i] == "--project-dir" and i + 1 < len(args):
            project_dir = args[i + 1]
            i += 2
        elif audio_file_path is None:
            audio_file_path = args[i]
            i += 1
        else:
            i += 1

    if not audio_file_path:
        print(json.dumps({"error": "Usage: python voice_processor.py <audio_file_path> [--project-dir <path>]"}))
        return

    logger.info(f"Audio file: {audio_file_path}")
    logger.info(f"Project dir: {project_dir}")

    try:
        processor = VoiceTerrainProcessor(project_dir=project_dir)
        result = processor.process_voice_command(audio_file_path)
        print(json.dumps(result, indent=2))
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()