import AVFAudio
import AVFoundation
import AppKit
import CoreAudio
import Foundation
import os
import whisper

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
  private var whisperSampleRate = Double(WHISPER_SAMPLE_RATE)

  private var audioBuffer: [Float] = []
  private var inputFormat: AVAudioFormat
  private var converter: AVAudioConverter?
  private var isRecording = false
  private var deviceChangeObservers: [NSObjectProtocol] = []
  private var currentAudioLevel: Float = 0.0

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

    // Always use the hardware format directly
    self.inputFormat = self.inputNode.inputFormat(forBus: 0)
      logger.info("Input hardware format: \(self.inputFormat.sampleRate) Hz")

    // let output = audioEngine.mainMixerNode
    // audioEngine.connect(inputNode, to: output, format: inputNode.inputFormat(forBus: 0))
    // audioEngine.prepare()
    // do {
    //     try audioEngine.start()
    //     print("Audio echo started")
    // } catch {
    //     print("Could not start audio engine: \(error.localizedDescription)")

    // }

    // Create converter to handle resampling to whisper model's expected format
    let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: whisperSampleRate, channels: 1,
      interleaved: false)!

    if inputFormat.sampleRate != whisperSampleRate {
        logger.info("Creating converter from \(self.inputFormat.sampleRate) Hz to \(self.whisperSampleRate) Hz")
      self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    } else {
      logger.info("No converter needed, formats match")
    }

    // Setup device change notification
    setupDeviceChangeListener()
  }

  private func setupDeviceChangeListener() {
    let notificationCenter = NotificationCenter.default

    // On macOS, we need to listen for system waking from sleep
    let wakeObserver = notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      Task {
        await self.handleDeviceChange()
      }
    }
    deviceChangeObservers.append(wakeObserver)

    // CoreAudio device property changes
    let devicePropertyObserver = notificationCenter.addObserver(
      forName: NSNotification.Name(rawValue: "com.apple.audio.CoreAudio.DevicePropertyChanged"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      Task {
        await self.handleDeviceChange()
      }
    }
    deviceChangeObservers.append(devicePropertyObserver)

    // CoreAudio device list changes
    let deviceListObserver = notificationCenter.addObserver(
      forName: NSNotification.Name(rawValue: "com.apple.audio.CoreAudio.DeviceListChanged"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      Task {
        await self.handleDeviceChange()
      }
    }
    deviceChangeObservers.append(deviceListObserver)

    logger.info("Audio device change listeners configured")
  }

  private func handleDeviceChange() async {
    logger.info("Audio device change detected")

    // If we're recording when the device changes, we need to restart the recording
    if isRecording {
      do {
        // Stop current recording
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)

        // Wait a bit for the system to complete the device change
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms

        // Reinitialize the audio engine and restart recording
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode

        // IMPORTANT: Get fresh input format from the new hardware device
        inputFormat = inputNode.inputFormat(forBus: 0)
          logger.info("New input format sample rate: \(self.inputFormat.sampleRate)")

        // Create new converter with the updated input format
        let inputFormatForConverter = AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1,
          interleaved: false)!
        let outputFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: whisperSampleRate, channels: 1,
          interleaved: false)!

        // Only create a new converter if the sample rates are different
        if inputFormat.sampleRate != whisperSampleRate {
          converter = AVAudioConverter(from: inputFormatForConverter, to: outputFormat)
        }

        // Restart recording
        try startRecording()
        logger.info("Successfully restarted recording after device change")
      } catch {
        logger.error(
          "Failed to restart recording after device change: \(error.localizedDescription)")
      }
    }
  }

  func startRecording() throws {
    // Always use the hardware input format directly
    // This ensures we match the hardware sample rate exactly
    let hardwareFormat = inputNode.inputFormat(forBus: 0)

    logger.info("Starting recording with format: \(hardwareFormat.sampleRate) Hz")

    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) {
      [weak self] buffer, _ in
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
      isRecording = true
    } catch {
      throw RecorderError.audioEngineError(
        "Could not start audio engine: \(error.localizedDescription)")
    }

    logger.info("Started recording")
  }

  private func processAudio(samples: [Float]) async {
    // Calculate RMS (Root Mean Square) for audio level
    let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
    let rms = sqrt(sumOfSquares / Float(samples.count))
    currentAudioLevel = min(rms * 10, 1.0) // Scale and clamp to 0-1
    
    if let downsampledChunk = downsample(samples) {
      audioBuffer.append(contentsOf: downsampledChunk)
    }
  }

  func stopRecording() {
    audioEngine.stop()
    inputNode.removeTap(onBus: 0)
    isRecording = false
    logger.info("Stopped recording, transcribing...")
  }

  deinit {
    for observer in deviceChangeObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func recordedDurationSeconds() -> Double {
    Double(audioBuffer.count) / whisperSampleRate
  }

  private func downsample(_ samples: [Float]) -> [Float]? {
    // If input format already matches whisper sample rate, no conversion needed
    if inputFormat.sampleRate == whisperSampleRate {
      return samples
    }

    // Otherwise use the converter
    guard let converter = converter else {
      logger.error(
        "Converter is nil but formats don't match: \(self.inputFormat.sampleRate) vs \(self.whisperSampleRate)"
      )
      return nil
    }

    let inputBuffer = AVAudioPCMBuffer(
      pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count))!
    let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: converter.outputFormat,
      frameCapacity: AVAudioFrameCount(
        Double(samples.count) * converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
      ))!

    inputBuffer.frameLength = inputBuffer.frameCapacity
    memcpy(inputBuffer.floatChannelData?[0], samples, samples.count * MemoryLayout<Float>.size)

    var error: NSError?
    let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return inputBuffer
    }

    guard status != .error, error == nil else {
      logger.error("Conversion failed: \(error?.localizedDescription ?? "Unknown error")")
      return nil
    }

    let downsampledData = UnsafeBufferPointer(
      start: outputBuffer.floatChannelData?[0], count: Int(outputBuffer.frameLength))
    return Array(downsampledData)
  }

  func getAudioLevel() -> Float {
    return currentAudioLevel
  }

  func transcribe() async -> String {
    await whisperContext.fullTranscribe(samples: audioBuffer)
    audioBuffer.removeAll()
    return await whisperContext.getTranscription().trimmingCharacters(in: .whitespaces)
  }
}
