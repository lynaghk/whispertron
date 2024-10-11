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
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        
        
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = standbyImage
        }
        
        setupMenus()
        
        let model_url = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")
        
        if let modelPath = model_url?.path {
            Task {
                do {
                    self.whisperContext = try await WhisperContext.createContext(path: modelPath)
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
