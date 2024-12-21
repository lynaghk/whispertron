import AVFoundation
import ApplicationServices
import Cocoa
import CoreGraphics
import Foundation
import HotKey
import SwiftUI
import os

class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var whisperContext: WhisperContext?
  private var recorder: Recorder?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
  private let standbyImage = NSImage(
    systemSymbolName: "circle", accessibilityDescription: "Standby")
  private let recordingImage = NSImage(
    systemSymbolName: "circle.fill", accessibilityDescription: "Recording")
  private var hotKey: HotKey?

  private var feedbackWindow: NSWindow?
  private var feedbackTextField: NSTextField?
  private var lastTranscript = ""
  private let MinimumTranscriptionDuration = 1.0
  func applicationDidFinishLaunching(_ aNotification: Notification) {

    self.hotKey = HotKey(key: .h, modifiers: [.control, .shift])
    hotKey?.keyDownHandler = { [weak self] in
      self?.didTapRecording()
    }
    hotKey?.keyUpHandler = { [weak self] in
      self?.didTapStandby()
    }

    setupFeedbackWindow()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = standbyImage
    setupMenus()

    guard
      let modelPath = Bundle.main.url(
        forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")?.path
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
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false)

    feedbackWindow?.level = .floating
    feedbackWindow?.isOpaque = true
    feedbackWindow?.hasShadow = true
    feedbackWindow?.ignoresMouseEvents = true

    feedbackTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
    feedbackTextField?.alignment = .center
    feedbackTextField?.isBezeled = false
    feedbackTextField?.drawsBackground = false
    feedbackTextField?.isEditable = false
    feedbackTextField?.isSelectable = false

    feedbackWindow?.contentView?.addSubview(feedbackTextField!)
  }

  func showFeedback(_ text: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let text = text {
        let mouseLocation = NSEvent.mouseLocation
        self.feedbackWindow?.setFrameOrigin(NSPoint(x: mouseLocation.x, y: mouseLocation.y))

        self.feedbackTextField?.stringValue = text
        self.feedbackWindow?.makeKeyAndOrderFront(nil)
      } else {
        self.feedbackWindow?.orderOut(nil)
      }
    }
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
    if let url = URL(string: "https://www.github.com/lynaghk") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func didTapStandby() {
    logger.debug("didTapStandby")
    showFeedback("transcribing...")
    statusItem.button?.image = standbyImage

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
    showFeedback("recording")
    statusItem.button?.image = recordingImage

    Task {
      do {
        try await recorder?.startRecording()
      } catch {
        logger.error("Error starting recording: \(error.localizedDescription)")
      }
    }
  }
}
