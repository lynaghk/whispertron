//
//  AppDelegate.swift
//  mt
//
//  Created by Kevin Lynagh on 9/27/24.
//

import Cocoa
import SwiftUI
import Foundation
import os
import AVFoundation
import HotKey


struct SwiftUIView: View {
    var body: some View {
        Text("Hello, SwiftUI!")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var whisperContext: WhisperContext?
    private var recorder: Recorder?
    
    // Create a logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
    
    // Create NSImage properties
    private let standbyImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Standby")
    private let recordingImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")
    private var hotKey: HotKey?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        
        
        //registerHotkey()
        self.hotKey = HotKey(key: .f12, modifiers: [.shift])
        hotKey?.keyDownHandler = {
            print("Down")
        }
        hotKey?.keyUpHandler = {
            print("Up")
        }

        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = standbyImage
        }
        
        setupMenus()
        
        let model_url = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")
        
        if let modelPath = model_url?.path {
            Task {
                do {
                    self.whisperContext = try WhisperContext.createContext(path: modelPath)
                    self.recorder = try await Recorder(whisperContext: self.whisperContext!)
                    logger.info("Whisper context and recorder created successfully")
                } catch {
                    logger.error("Error creating Whisper context: \(error.localizedDescription)")
                }
            }
        } else {
            logger.error("Could not find the model file")
        }
    }
    
    func setupMenus() {
        let menu = NSMenu()
        
        let standby = NSMenuItem(title: "Standby", action: #selector(didTapStandby) , keyEquivalent: "1")
        menu.addItem(standby)
        
        let recording = NSMenuItem(title: "Recording", action: #selector(didTapRecording) , keyEquivalent: "2")
        menu.addItem(recording)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        
        statusItem.menu = menu
    }
    
    @objc func didTapStandby() {
        if let button = statusItem.button {
            button.image = standbyImage
        }
        logger.debug("didTapStandby")
        
        Task {
            await recorder?.stopRecording()
        }
    }
    
    @objc func didTapRecording() {
        if let button = statusItem.button {
            button.image = recordingImage
        }
        logger.debug("didTapRecording")
        
        Task {
            do {
                try await recorder?.startRecording()
            } catch {
                logger.error("Error starting recording: \(error.localizedDescription)")
            }
        }
    }
    
}









//https://stackoverflow.com/questions/28281653/how-to-listen-to-global-hotkeys-with-swift-in-a-macos-app
import Carbon

extension String {
    /// This converts string to UInt as a fourCharCode
    public var fourCharCodeValue: Int {
        var result: Int = 0
        if let data = self.data(using: String.Encoding.macOSRoman) {
            data.withUnsafeBytes({ (rawBytes) in
                let bytes = rawBytes.bindMemory(to: UInt8.self)
                for i in 0 ..< data.count {
                    result = result << 8 + Int(bytes[i])
                }
            })
        }
        return result
    }
}

func getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = cocoaFlags.rawValue
    var newFlags: Int = 0
    
    if ((flags & NSEvent.ModifierFlags.control.rawValue) > 0) {
        newFlags |= controlKey
    }
    
    if ((flags & NSEvent.ModifierFlags.command.rawValue) > 0) {
        newFlags |= cmdKey
    }
    
    if ((flags & NSEvent.ModifierFlags.shift.rawValue) > 0) {
        newFlags |= shiftKey;
    }
    
    if ((flags & NSEvent.ModifierFlags.option.rawValue) > 0) {
        newFlags |= optionKey
    }
    
    if ((flags & NSEvent.ModifierFlags.capsLock.rawValue) > 0) {
        newFlags |= alphaLock
    }
    
    return UInt32(newFlags);
}

func registerHotkey() {
    var hotKeyRef: EventHotKeyRef?
    //let modifierFlags: UInt32 = getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags.command)
    let modifierFlags: UInt32 = 0
    
    let keyCode = kVK_RightShift
    var gMyHotKeyID = EventHotKeyID()
    
    gMyHotKeyID.id = UInt32(keyCode)
    gMyHotKeyID.signature = OSType("swat".fourCharCodeValue)
    
    var eventType = EventTypeSpec()
    eventType.eventClass = OSType(kEventClassKeyboard)
    eventType.eventKind = OSType(kEventHotKeyReleased)
    
    // Install handler.
    InstallEventHandler(GetApplicationEventTarget(), {
        (nextHandler, theEvent, userData) -> OSStatus in
        print("Key released")
        return noErr
        /// Check that hkCom in indeed your hotkey ID and handle it.
    }, 1, &eventType, nil, nil)
    
    // Register hotkey.
    let status = RegisterEventHotKey(UInt32(keyCode),
                                     modifierFlags,
                                     gMyHotKeyID,
                                     GetApplicationEventTarget(),
                                     0,
                                     &hotKeyRef)
    assert(status == noErr)
}
