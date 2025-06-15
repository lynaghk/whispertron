import AVFoundation
import ApplicationServices
import Cocoa
import CoreGraphics
import Foundation
import HotKey
import SwiftUI
import os

enum FeedbackState {
  case recording
  case transcribing
}

extension NSColor {
  convenience init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (1, 1, 1, 0)
    }
    
    self.init(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
  
  static var isDarkMode: Bool {
    return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var whisperContext: WhisperContext?
  private var recorder: Recorder?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
  private let standbyImage: NSImage = {
    let image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "Standby")!
    image.isTemplate = true
    return image
  }()
  private let recordingImage: NSImage = {
    let image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "Standby")!
    image.isTemplate = true
    return image
    // let config = NSImage.SymbolConfiguration(hierarchicalColor: NSColor(red: 0xFF/255.0, green: 0xA9/255.0, blue: 0x15/255.0, alpha: 1.0))
    // let image = NSImage(systemSymbolName: "ear.fill", accessibilityDescription: "Recording")!
    // return image.withSymbolConfiguration(config) ?? image
  }()
  private var hotKey: HotKey?
  
  private let windowSize: CGFloat = 200.0
  private let darkFg = NSColor(hex: "CCCCCC")
  private let lightFg = NSColor(hex: "333333")

  private var feedbackWindow: NSWindow?
  private var feedbackImageView: NSImageView?
  private var lastTranscript = ""
  private let MinimumTranscriptionDuration = 1.0
  private var audioLevelTimer: Timer?
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    
    DistributedNotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceChanged),
      name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil
    )

    self.hotKey = HotKey(key: .h, modifiers: [.control, .shift])
    hotKey?.keyDownHandler = { [weak self] in
      self?.didTapRecording()
    }
    hotKey?.keyUpHandler = { [weak self] in
      self?.didTapStandby()
    }

    // Configure audio session
    configureAudioSession()

    setupFeedbackWindow()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = standbyImage
    setupMenus()

    guard
      let modelPath = Bundle.main.url(
        forResource: "model", withExtension: "bin", subdirectory: "models")?.path
    else {
      logger.error("Could not find the model file")
      return
    }

    Task {
      do {
        self.whisperContext = try WhisperContext.createContext(path: modelPath)
        self.recorder = try await Recorder(whisperContext: self.whisperContext!)
        logger.info("Whisper context and recorder created successfully")
      } catch {
        logger.error("Error creating Whisper context: \(error.localizedDescription)")
      }
    }
  }

  private func configureAudioSession() {
    // On macOS, we rely on AVAudioEngine to handle device changes,
    // which is implemented in Recorder.swift
    logger.info("Audio session configuration for macOS")
  }

  // Translated from espanso's injectString function
  func insertStringAtCursor(_ string: String) {
    let udelay = UInt32(1000)

    DispatchQueue.main.async {
      let buffer = Array(string.utf16)

      // Because of a bug ( or undocumented limit ) of the CGEventKeyboardSetUnicodeString method
      // the string gets truncated after 20 characters, so we need to send multiple events.
      var i = 0
      let chunkSize = 20
      while i < buffer.count {
        let currentChunkSize = min(chunkSize, buffer.count - i)
        let offsetBuffer = Array(buffer[i..<(i + currentChunkSize)])

        if let e = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true) {
          e.keyboardSetUnicodeString(stringLength: currentChunkSize, unicodeString: offsetBuffer)
          e.post(tap: .cghidEventTap)
        }

        usleep(udelay)

        i += currentChunkSize
      }
    }
  }

  func setupFeedbackWindow() {
    feedbackWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: windowSize, height: windowSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false)

    feedbackWindow?.level = .floating
    feedbackWindow?.isOpaque = false
    feedbackWindow?.backgroundColor = NSColor.clear
    feedbackWindow?.hasShadow = false
    feedbackWindow?.ignoresMouseEvents = true
    
    // Create visual effect view for blur and transparency
    let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
    visualEffectView.material = .hudWindow
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = .active
    visualEffectView.wantsLayer = true
    visualEffectView.layer?.cornerRadius = 15
    visualEffectView.layer?.masksToBounds = true
    
    feedbackImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
    feedbackImageView?.imageAlignment = .alignCenter
    feedbackImageView?.imageScaling = .scaleProportionallyDown

    visualEffectView.addSubview(feedbackImageView!)
    feedbackWindow?.contentView = visualEffectView
  }

  func showFeedback(_ state: FeedbackState?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let state = state {
        if let screen = NSScreen.main {
          let screenFrame = screen.visibleFrame
          let centerX = screenFrame.midX - (windowSize / 2)
          let centerY: CGFloat = 140.0
          self.feedbackWindow?.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        let iconName = state == .recording ? "music.mic" : "pencil.and.outline"
        let accessibilityDescription = state == .recording ? "recording" : "transcribing"
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: accessibilityDescription)
        let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .medium)
        let coloredImage = image?.withSymbolConfiguration(config)
        
        self.feedbackImageView?.image = coloredImage
        updateFeedbackWindowAppearance()
        
        // Start pulsing for recording state
        if state == .recording {
          self.startAudioLevelPulsing()
        } else {
          self.stopAudioLevelPulsing()
        }
        
        self.feedbackWindow?.makeKeyAndOrderFront(nil)
      } else {
        self.stopAudioLevelPulsing()
        self.feedbackWindow?.orderOut(nil)
      }
    }
  }

  private func startAudioLevelPulsing() {
    audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.0333, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.recorder else { return }
      
      Task {
        let audioLevel = await recorder.getAudioLevel()
        DispatchQueue.main.async {
          var alpha = log2(1 + audioLevel * (64 - 1)) / log2(64)
          alpha = min(1.0, 0.3 + alpha)
          self.feedbackImageView?.alphaValue = CGFloat(alpha)
        }
      }
    }
  }

  private func stopAudioLevelPulsing() {
    audioLevelTimer?.invalidate()
    audioLevelTimer = nil
    feedbackImageView?.alphaValue = 1.0
  }

  //TODO: make this menu a microphone input selector?
  func setupMenus() {
    let menu = NSMenu()

    let about = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
    menu.addItem(about)

    menu.addItem(NSMenuItem.separator())

    let standby = NSMenuItem(title: "Standby", action: #selector(didTapStandby), keyEquivalent: "1")
    menu.addItem(standby)

    let recording = NSMenuItem(
      title: "Recording", action: #selector(didTapRecording), keyEquivalent: "2")
    menu.addItem(recording)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    statusItem.menu = menu
  }

  @objc func openAbout() {
    if let url = URL(string: "https://www.github.com/lynaghk/whispertron") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func didTapStandby() {
    logger.debug("didTapStandby")
    showFeedback(.transcribing)
    statusItem.button?.image = standbyImage
    statusItem.button?.cell?.isHighlighted = false

    Task {
      await recorder!.stopRecording()
      if await recorder!.recordedDurationSeconds() > MinimumTranscriptionDuration {
        lastTranscript = await recorder!.transcribe()
        self.insertStringAtCursor(lastTranscript)
      } else {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
      }
      showFeedback(nil)
    }
  }

  @objc func didTapRecording() {
    logger.debug("didTapRecording")
    showFeedback(.recording)
    statusItem.button?.image = recordingImage
    statusItem.button?.appearsDisabled = false
    statusItem.button?.cell?.isHighlighted = true

    Task {
      do {
        try await recorder?.startRecording()
      } catch {
        logger.error("Error starting recording: \(error.localizedDescription)")
      }
    }
  }
  
  @objc func appearanceChanged() {
    DispatchQueue.main.async { [weak self] in
      self?.updateFeedbackWindowAppearance()
    }
  }
  
  private func updateFeedbackWindowAppearance() {
    // guard let visualEffectView = feedbackWindow?.contentView as? NSVisualEffectView else { return }
    // Visual effect view automatically adapts to system appearance
    // visualEffectView.material = .hudWindow
    feedbackImageView?.contentTintColor = NSColor.isDarkMode ? darkFg : lightFg
  }
}
