//
//  AppDelegate.swift
//  mt
//
//  Created by Kevin Lynagh on 9/27/24.
//

import Cocoa
import SwiftUI
import Foundation

struct SwiftUIView: View {
    var body: some View {
        Text("Hello, SwiftUI!")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var whisperContext: WhisperContext?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "1.circle", accessibilityDescription: "1")
        }
        
        setupMenus()
        
        let model_url = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")
        
        if let modelPath = model_url?.path {
            Task {
                do {
                    self.whisperContext = try await WhisperContext.createContext(path: modelPath)
                    print("Whisper context created successfully")
                } catch {
                    print("Error creating Whisper context: \(error)")
                }
            }
        } else {
            print("Error: Could not find the model file")
        }
    }
    
    func setupMenus() {
        let menu = NSMenu()

        let one = NSMenuItem(title: "One", action: #selector(didTapOne) , keyEquivalent: "1")
        menu.addItem(one)

        let two = NSMenuItem(title: "Two", action: #selector(didTapTwo) , keyEquivalent: "2")
        menu.addItem(two)

        let three = NSMenuItem(title: "Three", action: #selector(didTapThree) , keyEquivalent: "3")
        menu.addItem(three)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // 3
        statusItem.menu = menu
    }
    
    private func changeStatusBarButton(number: Int) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "\(number).circle", accessibilityDescription: number.description)
        }
    }

    @objc func didTapOne() {
        changeStatusBarButton(number: 1)
        print("didTapOne")
    }

    @objc func didTapTwo() {
        changeStatusBarButton(number: 2)
    }

    @objc func didTapThree() {
        changeStatusBarButton(number: 3)
    }
}
