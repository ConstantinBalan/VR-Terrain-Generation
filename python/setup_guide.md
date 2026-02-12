# Voice-to-Terrain Setup Guide

This guide helps you set up the voice-controlled terrain generation system.

## Prerequisites

1. **Python 3.8+** installed on your system
2. **OpenAI API Key** (get one from https://platform.openai.com/)

## Installation Steps

### 1. Install Python Dependencies

Open a command prompt in the `python/` directory and run:

```bash
pip install -r requirements.txt
```

This will install:
- OpenAI API client
- Whisper for speech-to-text
- Required audio processing libraries

### 2. Configure OpenAI API Key

You have two options:

**Option A: Environment Variable (Recommended)**
```bash
# Windows (Command Prompt)
set OPENAI_API_KEY=your_api_key_here

# Windows (PowerShell)
$env:OPENAI_API_KEY="your_api_key_here"

# Linux/Mac
export OPENAI_API_KEY="your_api_key_here"
```

**Option B: API Key File**
Create a file called `openai_key.txt` in the `python/` directory with your API key:
```
your_api_key_here
```

### 3. Test the Setup

Test the voice processor with a sample audio file:

```bash
# Create a test audio file (or record one)
python voice_processor.py "path/to/test_audio.wav"
```

Expected output:
```json
{
  "text": "I want some mountains",
  "parameters": {
	"seed": 1234,
	"frequency": 0.05,
	"amplitude": 15.0,
	"octaves": 3,
	"lacunarity": 2.0,
	"persistence": 0.5,
	"terrain_type": 2,
	"erosion": 0.0,
	"plateau": 0.0
  },
  "keywords": ["mountains"],
  "success": true
}
```

## VR Controller Setup

In your Godot project:

1. **Add VoiceTerrainController to your scene:**
   - Add the script to a Node in your main VR scene
   - Set the `python_script_path` to point to `voice_processor.py`

2. **Input Mapping:**
   - Left controller grip button = Start/stop voice recording
   - Right controller trigger = Select terrain placement location

3. **Usage Flow:**
   - Point right controller at desired location
   - Press trigger to select location
   - Hold left grip button and speak terrain description
   - Release grip button to process and generate terrain

## Voice Commands Examples

The system understands natural language descriptions:

- **"I want rolling hills"** → Creates gentle hilly terrain
- **"Make some mountains"** → Generates mountainous terrain
- **"Create a flat area"** → Makes flat terrain
- **"Build valleys with a river"** → Creates valleys with erosion
- **"Make rough rocky mountains"** → High detail mountain terrain
- **"Smooth gentle hills"** → Low detail, soft hills

## Troubleshooting

### "OpenAI library not installed"
```bash
pip install openai
```

### "Whisper library not installed"
```bash
pip install openai-whisper
```

### "OPENAI_API_KEY not found"
- Check that your API key is set correctly
- Verify the API key is valid at https://platform.openai.com/

### Audio Recording Issues
- Ensure microphone permissions are granted to Godot
- Check that the "Record" audio bus is created in Godot's audio settings

### Python Script Not Found
- Verify the path in `VoiceTerrainController.python_script_path`
- Use absolute paths if relative paths don't work

## Performance Notes

- **Whisper Model Size:** The script uses "base" model for speed. For better accuracy, change to "small" or "medium" in `voice_processor.py`
- **OpenAI API Costs:** GPT-3.5-turbo is used for cost efficiency. Upgrade to GPT-4 for better terrain understanding
- **Offline Mode:** The system includes fallback keyword matching if APIs are unavailable

## Integration with Godot

The system is designed to work with your existing VR terrain generation project:

1. **VoiceTerrainController.gd** handles VR integration and audio recording
2. **voice_processor.py** processes audio and returns terrain parameters
3. **TerrainChunk.gd** generates the actual terrain mesh
4. **GridManager.gd** manages placement and grid coordination

The voice system integrates seamlessly with your current interaction flow while adding voice control capabilities.
