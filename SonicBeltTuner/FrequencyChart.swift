import SwiftUI

struct FrequencyChart: View {
    let frequencies: [Float]
    let amplitudes: [Float]
    let peakFrequency: Float
    
    private let maxDisplayFrequency: Float = 400.00
    private let xAxisMarkers: [Float] = [0, 50, 100, 150, 200, 250, 300, 350, 400]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .border(Color.gray, width: 1)
                
                // X-axis grid lines and labels
                ForEach(xAxisMarkers, id: \.self) { frequency in
                    let x = CGFloat(frequency / maxDisplayFrequency) * geometry.size.width
                    
                    // Grid line
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    
                    // Frequency label
                    VStack {
                        Spacer()
                        Text("\(Int(frequency))")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .position(x: x, y: geometry.size.height - 10)
                    }
                }
                
                if !frequencies.isEmpty && !amplitudes.isEmpty {
                    // Spectrum curve
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height - 20 // Leave space for labels
                        let maxAmplitude = amplitudes.max() ?? 1.0
                        
                        for (index, amplitude) in amplitudes.enumerated() {
                            guard index < frequencies.count else { break }
                            
                            let frequency = frequencies[index]
                            let x = CGFloat(frequency / maxDisplayFrequency) * width
                            let y = height - (CGFloat(amplitude) / CGFloat(maxAmplitude)) * height
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.green, lineWidth: 2)
                    
                    // Peak frequency marker
                    if peakFrequency > 0 && peakFrequency <= maxDisplayFrequency {
                        let peakX = CGFloat(peakFrequency / maxDisplayFrequency) * geometry.size.width
                        
                        Path { path in
                            path.move(to: CGPoint(x: peakX, y: 0))
                            path.addLine(to: CGPoint(x: peakX, y: geometry.size.height - 20))
                        }
                        .stroke(Color.red, lineWidth: 3)
                        .opacity(0.9)
                        
                        // Peak frequency label
                        Text(String(format: "%.1f Hz", peakFrequency))
                            .font(.caption)
                            .foregroundColor(.red)
                            .background(Color.black.opacity(0.7))
                            .position(x: min(max(peakX, 40), geometry.size.width - 40), y: 15)
                    }
                }
                
                // Chart labels
                VStack {
                    HStack {
                        Text("Frequency (Hz)")
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                        Text("0 - 400 Hz")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    
                    Spacer()
                }
            }
        }
        .frame(height: 250)
    }
}
