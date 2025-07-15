# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SonicBeltTuner is an iOS application for measuring 3D printer belt tension through audio frequency analysis. The app uses the iPhone's microphone to detect the resonant frequency of plucked belts, helping users achieve optimal belt tension.

## Build Commands

```bash
# Build for iOS Simulator
xcodebuild -project SonicBeltTuner.xcodeproj -scheme SonicBeltTuner -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build for device
xcodebuild -project SonicBeltTuner.xcodeproj -scheme SonicBeltTuner -destination 'generic/platform=iOS' build

# Clean build
xcodebuild -project SonicBeltTuner.xcodeproj -scheme SonicBeltTuner clean
```

## Architecture

### Core Components

1. **AudioManager** (`AudioManager.swift`)
   - ObservableObject managing all audio processing
   - Handles microphone access via AVAudioEngine
   - Performs FFT analysis using Accelerate framework
   - Key features:
     - Real-time FFT with configurable window functions (Blackman, Hanning, Hamming)
     - Multiple peak detection algorithms (Simple, Parabolic Interpolation, Spectral Centroid)
     - Harmonic suppression to isolate fundamental frequency
     - RMS averaging and temporal smoothing
   - Frequency range: 0-400Hz (configurable via `maxFrequency`)

2. **FrequencyChart** (`FrequencyChart.swift`)
   - Custom SwiftUI visualization component
   - Displays real-time frequency spectrum with grid lines
   - Shows peak frequency marker with exact value
   - X-axis: 0-400Hz with markers every 50Hz
   - Automatically scales amplitude to full chart height

3. **ContentView** (`ContentView.swift`)
   - Main UI with NavigationView for safe area handling
   - Controls for window function, peak detection method, harmonic filtering, and smoothing
   - Belt status indicator based on frequency ranges:
     - < 50Hz: Very Loose
     - 50-82Hz: Loose  
     - 82-88Hz: Good (optimal for Prusa MK3/4)
     - 88-150Hz: Tight
     - > 150Hz: Very Tight

### Signal Processing Pipeline

1. Audio capture at device's native format (typically 48kHz)
2. Accumulation into 1024-sample buffers
3. Window function application
4. FFT computation (512-point real FFT)
5. RMS averaging across 10 frames
6. Harmonic suppression (reduces 2x-6x harmonics by 80%)
7. Peak detection with sub-bin accuracy
8. Temporal smoothing of peak frequency

### Key Technical Details

- **Microphone Permission**: Set in project settings as `INFOPLIST_KEY_NSMicrophoneUsageDescription`
- **FFT Size**: 1024 samples (provides ~43Hz resolution at 44.1kHz)
- **Buffer Size**: 512 samples for audio tap
- **Supported iOS**: 18.5+ (deployment target)
- **Audio Session**: Uses `.record` category with `.measurement` mode

## Testing Audio Features

To test audio processing changes:
1. Run on physical device (simulator microphone may behave differently)
2. Use a known frequency source (tone generator app) to verify accuracy
3. Check console output for audio format details
4. Test with actual 3D printer belts in 50-200Hz range

## Common Issues

- **Format Mismatch Error**: AudioManager uses `format: nil` in installTap to accept device's native format
- **Red Marker Not Moving**: Ensure peak frequency calculation uses actual frequency values, not array indices
- **Harmonic Interference**: Toggle harmonic filtering to isolate fundamental frequency