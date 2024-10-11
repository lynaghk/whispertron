import Foundation
import AVFoundation
import whisper
import AVFAudio
import CoreAudio
import os

func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            continuation.resume(returning: granted)
        }
    }
}

actor Recorder {
    private var audioEngine: AVAudioEngine
    private var whisperContext: WhisperContext
    private var inputNode: AVAudioInputNode
    private var bufferSize: AVAudioFrameCount = 1024
    //private var sampleRate: Double = 16000.0
    private var sampleRate: Double = Double(WHISPER_SAMPLE_RATE)
    private var audioBuffer: [Float] = []
    private var inputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Recorder")

    
    
    enum RecorderError: Error {
        case audioEngineError(String)
    }
    
    init(whisperContext: WhisperContext) async throws {
        self.whisperContext = whisperContext
        self.audioEngine = AVAudioEngine()
        self.inputNode = audioEngine.inputNode
        
        let granted = await requestMicrophonePermission()
        if granted {
            self.logger.info("Microphone permission granted")
        } else {
            self.logger.error("Microphone permission not granted")
            throw RecorderError.audioEngineError("Microphone permission denied")
        }
        
        self.inputFormat = self.inputNode.inputFormat(forBus: 0)

        print("Native sample rate: \(sampleRate)")
        
        
        
        
        
        
        
        let inputDescription = inputNode.inputFormat(forBus: 0).description
        let portDescription = inputNode.auAudioUnit.inputBusses[0].supportedChannelLayoutTags
        
        print("Input Description: \(inputDescription)")
        print("Port Description: \(portDescription)")
        
    
        let output = audioEngine.mainMixerNode
        
        audioEngine.connect(inputNode, to: output, format: inputNode.inputFormat(forBus: 0))
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("Audio echo started")
        } catch {
            print("Could not start audio engine: \(error.localizedDescription)")

        }

        
        
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: self.inputFormat.sampleRate, channels: 1, interleaved: false)!
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WHISPER_SAMPLE_RATE), channels: 1, interleaved: false)!
        self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    }
    
    func startRecording() throws {
        let sampleRate = self.inputFormat.sampleRate
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            
            if let channelData = channelData {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                Task {
                    await self.processAudio(samples: samples)
                }
            }
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            throw RecorderError.audioEngineError("Could not start audio engine: \(error.localizedDescription)")
        }
        
        print("Started recording")
    }
    
    func stopRecording() {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        audioBuffer.removeAll()
        print("Stopped recording")
    }
    
    private func processAudio(samples: [Float]) async {
        audioBuffer.append(contentsOf: samples)
        let inputSampleRate = self.inputFormat.sampleRate
        let whisperSampleRate = Double(WHISPER_SAMPLE_RATE)
        let chunkDuration = 3.0 // 3 seconds
        let inputChunkSize = Int(inputSampleRate * chunkDuration)
        
        while audioBuffer.count >= inputChunkSize {
            let chunk = Array(audioBuffer.prefix(inputChunkSize))
            audioBuffer.removeFirst(inputChunkSize)
            
            if let downsampledChunk = downsample(chunk) {
                await transcribeChunk(downsampledChunk)
            }
        }
    }
    
    private func downsample(_ samples: [Float]) -> [Float]? {
        guard let converter = converter else { return nil }
        
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(Double(samples.count) * converter.outputFormat.sampleRate / converter.inputFormat.sampleRate))!
        
        inputBuffer.frameLength = inputBuffer.frameCapacity
        memcpy(inputBuffer.floatChannelData?[0], samples, samples.count * MemoryLayout<Float>.size)
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        guard status != .error, error == nil else {
            print("Conversion failed: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        let downsampledData = UnsafeBufferPointer(start: outputBuffer.floatChannelData?[0], count: Int(outputBuffer.frameLength))
        return Array(downsampledData)
    }
    
    private func transcribeChunk(_ chunk: [Float]) async {
        do {
            try await whisperContext.fullTranscribe(samples: chunk)
            let transcription = await whisperContext.getTranscription()
            print("Transcription: \(transcription)")
        } catch {
            print("Error transcribing audio: \(error.localizedDescription)")
        }
    }
}
