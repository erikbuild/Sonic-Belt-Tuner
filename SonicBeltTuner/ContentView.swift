//
//  ContentView.swift
//  SonicBeltTuner
//
//  Created by Erik Reynolds on 7/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Sonic Belt Tuner")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top, 10)
                    
                    Text("3D Printer Belt Tension Analyzer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Peak Frequency:")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.1f Hz", audioManager.peakFrequency))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)
                
                HStack {
                    Text("Belt Status:")
                        .font(.headline)
                    Spacer()
                    Text(getBeltStatus(frequency: audioManager.peakFrequency))
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(getBeltStatusColor(frequency: audioManager.peakFrequency))
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            FrequencyChart(
                frequencies: audioManager.frequencies,
                amplitudes: audioManager.amplitudes,
                peakFrequency: audioManager.peakFrequency
            )
            .padding(.horizontal)
            
            Button(action: {
                if audioManager.isRecording {
                    audioManager.stopRecording()
                } else {
                    audioManager.startRecording()
                }
            }) {
                HStack {
                    Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(audioManager.isRecording ? "Stop Analysis" : "Start Analysis")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(audioManager.isRecording ? Color.red : Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Window Function:")
                        .font(.headline)
                    Spacer()
                    Picker("Window", selection: $audioManager.windowFunction) {
                        ForEach(WindowFunction.allCases, id: \.self) { window in
                            Text(window.rawValue).tag(window)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 120)
                }
                
                HStack {
                    Text("Peak Detection:")
                        .font(.headline)
                    Spacer()
                    Picker("Peak Method", selection: $audioManager.peakDetectionMethod) {
                        ForEach(PeakDetectionMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 160)
                }
                
                HStack {
                    Text("Harmonic Filtering:")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $audioManager.useHarmonicFiltering)
                        .labelsHidden()
                }
                
                HStack {
                    Text("Smoothing:")
                        .font(.headline)
                    Spacer()
                    Slider(value: $audioManager.smoothingFactor, in: 0.1...0.9, step: 0.1)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.1f", audioManager.smoothingFactor))
                        .font(.caption)
                        .frame(width: 25)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions:")
                        .font(.headline)
                    Text("1. Press 'Start Analysis' to begin listening")
                    Text("2. Gently pluck your 3D printer belt to create vibrations")
                    Text("3. The peak frequency will indicate belt tension")
                    Text("4. Optimal range: ~85 Hz for Prusa MK3/4 X & Y belts")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
            
                    Spacer(minLength: 20)
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func getBeltStatus(frequency: Float) -> String {
        switch frequency {
        case 0..<50:
            return "Very Loose"
        case 50..<82:
            return "Loose"
        case 82..<88:
            return "Good"
        case 88..<150:
            return "Tight"
        case 150..<500:
            return "Very Tight"
        default:
            return "Check Setup"
        }
    }
    
    private func getBeltStatusColor(frequency: Float) -> Color {
        switch frequency {
        case 0..<50:
            return .red
        case 50..<82:
            return .orange
        case 82..<88:
            return .green
        case 88..<150:
            return .blue
        case 150..<500:
            return .purple
        default:
            return .gray
        }
    }
}

#Preview {
    ContentView()
}
