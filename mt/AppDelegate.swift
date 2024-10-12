import Cocoa
import SwiftUI
import Foundation
import os
import AVFoundation
import HotKey
import ApplicationServices
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var whisperContext: WhisperContext?
    private var recorder: Recorder?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
    private let standbyImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Standby")
    private let recordingImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")
    private var hotKey: HotKey?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {

        self.hotKey = HotKey(key: .h, modifiers: [.control, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.didTapRecording()
        }
        hotKey?.keyUpHandler = { [weak self] in
            self?.didTapStandby()
        }
        
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = standbyImage
        setupMenus()
        
        guard let modelPath = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")?.path else {
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
    
    func insertStringAtCursor(_ string: String) {
        let udelay = UInt32(1000)
        
        DispatchQueue.main.async {
            // Convert the string to a [UniChar] array as required by the CGEventKeyboardSetUnicodeString method
            let buffer = Array(string.utf16)
            
            
            // Because of a bug ( or undocumented limit ) of the CGEventKeyboardSetUnicodeString method
            // the string gets truncated after 20 characters, so we need to send multiple events.
            
            var i = 0
            let chunkSize = 20;
            while i < buffer.count {
                let currentChunkSize = min(chunkSize, buffer.count - i)
                let offsetBuffer = Array(buffer[i..<(i+currentChunkSize)])
                
                if let e = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true) {
                    e.keyboardSetUnicodeString(stringLength: currentChunkSize, unicodeString: offsetBuffer)
                    e.post(tap: .cghidEventTap)
                }
                
                usleep(udelay)
                
                i += currentChunkSize
            }
        }
    }
    
    //TODO: make this menu a microphone input selector?
    func setupMenus() {
        let menu = NSMenu()
        
        let about = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(about)
        
        menu.addItem(NSMenuItem.separator())
        
        let standby = NSMenuItem(title: "Standby", action: #selector(didTapStandby) , keyEquivalent: "1")
        menu.addItem(standby)
        
        let recording = NSMenuItem(title: "Recording", action: #selector(didTapRecording) , keyEquivalent: "2")
        menu.addItem(recording)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func openAbout() {
        if let url = URL(string: "https://www.github.com/lynaghk") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func didTapStandby() {
        logger.debug("didTapStandby")
        statusItem.button?.image = standbyImage
        Task {
            guard let transcript = await recorder?.stopRecording() else {
                logger.debug("No transcript to copy")
                return
            }
            // NSPasteboard.general.clearContents()
            // NSPasteboard.general.setString(transcript, forType: .string)
            self.insertStringAtCursor(transcript)
        }
    }
    
    @objc func didTapRecording() {
        logger.debug("didTapRecording")
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
