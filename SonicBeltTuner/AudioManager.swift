import Foundation
import AVFoundation
import Accelerate
import Combine

enum WindowFunction: String, CaseIterable {
    case none = "None"
    case blackman = "Blackman"
    case hanning = "Hanning"
    case hamming = "Hamming"
}

enum PeakDetectionMethod: String, CaseIterable {
    case simple = "Simple Peak"
    case parabolic = "Parabolic Interpolation"
    case centroid = "Spectral Centroid"
}

class AudioManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode!
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    
    @Published var isRecording = false
    @Published var frequencies: [Float] = []
    @Published var amplitudes: [Float] = []
    @Published var peakFrequency: Float = 0.0
    @Published var windowFunction: WindowFunction = .blackman
    @Published var peakDetectionMethod: PeakDetectionMethod = .parabolic
    @Published var useHarmonicFiltering: Bool = true
    @Published var smoothingFactor: Float = 0.3
    
    private let sampleRate: Float = 44100.0
    private let maxFrequency: Float = 400.0
    
    // RMS and smoothing buffers
    private var magnitudeHistory: [[Float]] = []
    private var peakFrequencyHistory: [Float] = []
    private let historySize = 10
    
    init() {
        setupAudio()
        setupFFT()
    }
    
    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    private func setupAudio() {
        inputNode = audioEngine.inputNode
        
        // Use the input node's exact output format - this is the safest approach
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("Input format: \(inputFormat)")
        
        // Use a buffer size that's compatible with the format
        let bufferSize = AVAudioFrameCount(512)
        
        // Install tap with nil format to use the input node's format
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }
    
    private func setupFFT() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.frequencies = []
            self.amplitudes = []
            self.peakFrequency = 0.0
            self.audioBuffer = []
            self.magnitudeHistory = []
            self.peakFrequencyHistory = []
        }
        
        setupAudio()
    }
    
    private var audioBuffer = [Float]()
    
    private func applyWindow(to data: [Float]) -> [Float] {
        guard data.count > 0 else { return data }
        
        switch windowFunction {
        case .none:
            return data
        case .blackman:
            return applyBlackmanWindow(to: data)
        case .hanning:
            return applyHanningWindow(to: data)
        case .hamming:
            return applyHammingWindow(to: data)
        }
    }
    
    private func applyBlackmanWindow(to data: [Float]) -> [Float] {
        let N = data.count
        var windowed = [Float](repeating: 0.0, count: N)
        
        for i in 0..<N {
            let n = Float(i)
            let Nf = Float(N - 1)
            let window = 0.42 - 0.5 * cos(2.0 * Float.pi * n / Nf) + 0.08 * cos(4.0 * Float.pi * n / Nf)
            windowed[i] = data[i] * window
        }
        
        return windowed
    }
    
    private func applyHanningWindow(to data: [Float]) -> [Float] {
        let N = data.count
        var windowed = [Float](repeating: 0.0, count: N)
        
        for i in 0..<N {
            let n = Float(i)
            let Nf = Float(N - 1)
            let window = 0.5 * (1.0 - cos(2.0 * Float.pi * n / Nf))
            windowed[i] = data[i] * window
        }
        
        return windowed
    }
    
    private func applyHammingWindow(to data: [Float]) -> [Float] {
        let N = data.count
        var windowed = [Float](repeating: 0.0, count: N)
        
        for i in 0..<N {
            let n = Float(i)
            let Nf = Float(N - 1)
            let window = 0.54 - 0.46 * cos(2.0 * Float.pi * n / Nf)
            windowed[i] = data[i] * window
        }
        
        return windowed
    }
    
    private func findPeakCenterFrequency(magnitudes: [Float], frequencies: [Float]) -> Float {
        guard !magnitudes.isEmpty else { return 0.0 }
        
        // Find the peak bin
        guard let maxIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return 0.0
        }
        
        // Ensure we have neighboring bins for interpolation
        guard maxIndex > 0 && maxIndex < magnitudes.count - 1 else {
            return frequencies[maxIndex]
        }
        
        // Use parabolic interpolation to find the true peak center
        let y1 = magnitudes[maxIndex - 1]
        let y2 = magnitudes[maxIndex]
        let y3 = magnitudes[maxIndex + 1]
        
        // Parabolic interpolation formula
        let a = (y1 - 2*y2 + y3) / 2
        let b = (y3 - y1) / 2
        
        // Avoid division by zero
        guard abs(a) > 1e-10 else {
            return frequencies[maxIndex]
        }
        
        // Peak offset from the max bin
        let peakOffset = -b / (2 * a)
        
        // Clamp the offset to reasonable bounds
        let clampedOffset = max(-1.0, min(1.0, peakOffset))
        
        // Calculate the interpolated frequency
        let frequencyResolution = frequencies.count > 1 ? frequencies[1] - frequencies[0] : 1.0
        let interpolatedFrequency = frequencies[maxIndex] + clampedOffset * frequencyResolution
        
        return interpolatedFrequency
    }
    
    private func findSpectralCentroid(magnitudes: [Float], frequencies: [Float]) -> Float {
        guard magnitudes.count == frequencies.count && !magnitudes.isEmpty else { return 0.0 }
        
        // Find the peak and define a region around it
        guard let maxIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return 0.0
        }
        
        let maxAmplitude = magnitudes[maxIndex]
        let threshold = maxAmplitude * 0.5 // -6dB threshold
        
        // Find the region around the peak above threshold
        var startIndex = maxIndex
        var endIndex = maxIndex
        
        // Expand left
        while startIndex > 0 && magnitudes[startIndex - 1] > threshold {
            startIndex -= 1
        }
        
        // Expand right
        while endIndex < magnitudes.count - 1 && magnitudes[endIndex + 1] > threshold {
            endIndex += 1
        }
        
        // Calculate weighted centroid in the peak region
        var weightedSum: Float = 0.0
        var totalWeight: Float = 0.0
        
        for i in startIndex...endIndex {
            let weight = magnitudes[i]
            weightedSum += frequencies[i] * weight
            totalWeight += weight
        }
        
        return totalWeight > 0 ? weightedSum / totalWeight : frequencies[maxIndex]
    }
    
    private func applyRMSAveraging(magnitudes: [Float]) -> [Float] {
        // Add current magnitudes to history
        magnitudeHistory.append(magnitudes)
        
        // Keep only recent history
        if magnitudeHistory.count > historySize {
            magnitudeHistory.removeFirst()
        }
        
        guard !magnitudeHistory.isEmpty else { return magnitudes }
        
        // Calculate RMS average across time
        var rmsAveraged = [Float](repeating: 0.0, count: magnitudes.count)
        
        for i in 0..<magnitudes.count {
            var sumSquares: Float = 0.0
            var count: Float = 0.0
            
            for historyFrame in magnitudeHistory {
                if i < historyFrame.count {
                    sumSquares += historyFrame[i] * historyFrame[i]
                    count += 1.0
                }
            }
            
            rmsAveraged[i] = count > 0 ? sqrt(sumSquares / count) : 0.0
        }
        
        return rmsAveraged
    }
    
    private func suppressHarmonics(magnitudes: [Float], frequencies: [Float]) -> [Float] {
        guard useHarmonicFiltering && magnitudes.count == frequencies.count else { return magnitudes }
        
        var filtered = magnitudes
        let fundamentalRange = 50.0...200.0 // Typical belt fundamental range
        
        // Find the strongest peak in the fundamental range
        var fundamentalPeak: (index: Int, frequency: Float, amplitude: Float) = (0, 0, 0)
        
        for (index, frequency) in frequencies.enumerated() {
            if fundamentalRange.contains(Double(frequency)) && magnitudes[index] > fundamentalPeak.amplitude {
                fundamentalPeak = (index, frequency, magnitudes[index])
            }
        }
        
        guard fundamentalPeak.amplitude > 0 else { return filtered }
        
        // Suppress likely harmonics
        let harmonicTolerance: Float = 10.0 // Hz tolerance for harmonic detection
        
        for harmonic in 2...6 { // Check up to 6th harmonic
            let expectedHarmonic = fundamentalPeak.frequency * Float(harmonic)
            
            for (index, frequency) in frequencies.enumerated() {
                if abs(frequency - expectedHarmonic) < harmonicTolerance {
                    // Suppress harmonic but don't eliminate completely
                    filtered[index] *= 0.2
                }
            }
        }
        
        return filtered
    }
    
    private func smoothPeakFrequency(_ newPeakFrequency: Float) -> Float {
        // Add to history
        peakFrequencyHistory.append(newPeakFrequency)
        
        // Keep only recent history
        if peakFrequencyHistory.count > historySize {
            peakFrequencyHistory.removeFirst()
        }
        
        guard !peakFrequencyHistory.isEmpty else { return newPeakFrequency }
        
        // Apply exponential smoothing
        var smoothed = peakFrequencyHistory[0]
        
        for i in 1..<peakFrequencyHistory.count {
            smoothed = smoothingFactor * smoothed + (1.0 - smoothingFactor) * peakFrequencyHistory[i]
        }
        
        return smoothed
    }
    
    private func findFundamentalFrequency(magnitudes: [Float], frequencies: [Float]) -> Float {
        guard !magnitudes.isEmpty && magnitudes.count == frequencies.count else { return 0.0 }
        
        // Focus on the fundamental frequency range for belts (50-200 Hz)
        let fundamentalRange = 50.0...200.0
        var fundamentalCandidates: [(frequency: Float, amplitude: Float)] = []
        
        for (index, frequency) in frequencies.enumerated() {
            if fundamentalRange.contains(Double(frequency)) {
                fundamentalCandidates.append((frequency, magnitudes[index]))
            }
        }
        
        guard !fundamentalCandidates.isEmpty else {
            // Fallback to original method if no candidates in fundamental range
            return findPeakCenterFrequency(magnitudes: magnitudes, frequencies: frequencies)
        }
        
        // Find the strongest peak in the fundamental range
        let strongestFundamental = fundamentalCandidates.max { $0.amplitude < $1.amplitude }
        return strongestFundamental?.frequency ?? 0.0
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let fftSetup = fftSetup,
              let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Convert multi-channel to mono by averaging channels
        var monoData = [Float]()
        for frameIndex in 0..<frameCount {
            var sum: Float = 0.0
            for channelIndex in 0..<channelCount {
                sum += channelData[channelIndex][frameIndex]
            }
            monoData.append(sum / Float(channelCount))
        }
        
        // Accumulate audio data until we have enough for FFT
        audioBuffer.append(contentsOf: monoData)
        
        // Only process when we have enough data
        guard audioBuffer.count >= fftSize else { return }
        
        // Use the buffer's actual sample rate
        let bufferSampleRate = Float(buffer.format.sampleRate)
        
        // Take the most recent fftSize samples
        let audioData = Array(audioBuffer.suffix(fftSize))
        audioBuffer = Array(audioBuffer.suffix(fftSize / 2)) // Keep some overlap
        
        // Apply windowing function to reduce spectral leakage
        let windowedData = applyWindow(to: audioData)
        
        var realParts = [Float](repeating: 0.0, count: fftSize / 2)
        var imagParts = [Float](repeating: 0.0, count: fftSize / 2)
        
        // Copy windowed audio data to real parts (first half only for real FFT)
        for i in 0..<min(windowedData.count / 2, realParts.count) {
            realParts[i] = windowedData[i * 2] // Downsample by taking every 2nd sample
        }
        
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBaseAddress = realPtr.baseAddress,
                      let imagBaseAddress = imagPtr.baseAddress else { return }
                
                var complexBuffer = DSPSplitComplex(realp: realBaseAddress, imagp: imagBaseAddress)
                
                vDSP_fft_zrip(fftSetup, &complexBuffer, 1, vDSP_Length(log2(Float(fftSize))), Int32(kFFTDirection_Forward))
                
                var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvmags(&complexBuffer, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                let frequencyResolution = bufferSampleRate / Float(fftSize)
                let maxBin = Int(maxFrequency / frequencyResolution)
                var filteredMagnitudes = Array(magnitudes[0..<min(maxBin, magnitudes.count)])
                
                let newFrequencies = (0..<filteredMagnitudes.count).map { Float($0) * frequencyResolution }
                
                // Apply RMS averaging for noise reduction
                filteredMagnitudes = self.applyRMSAveraging(magnitudes: filteredMagnitudes)
                
                // Apply harmonic suppression to isolate fundamental
                filteredMagnitudes = self.suppressHarmonics(magnitudes: filteredMagnitudes, frequencies: newFrequencies)
                
                // Use the selected peak detection method with fundamental frequency bias
                let rawPeakFrequency: Float
                switch self.peakDetectionMethod {
                case .simple:
                    rawPeakFrequency = self.findFundamentalFrequency(magnitudes: filteredMagnitudes, frequencies: newFrequencies)
                case .parabolic:
                    rawPeakFrequency = self.findPeakCenterFrequency(magnitudes: filteredMagnitudes, frequencies: newFrequencies)
                case .centroid:
                    rawPeakFrequency = self.findSpectralCentroid(magnitudes: filteredMagnitudes, frequencies: newFrequencies)
                }
                
                // Apply temporal smoothing to reduce jitter
                let smoothedPeakFrequency = self.smoothPeakFrequency(rawPeakFrequency)
                
                DispatchQueue.main.async {
                    self.frequencies = newFrequencies
                    self.amplitudes = filteredMagnitudes
                    self.peakFrequency = smoothedPeakFrequency
                }
            }
        }
    }
}
