import Cocoa
import HotKey
import os

protocol HotkeyRecorderDelegate: AnyObject {
    func hotkeyRecorder(_ recorder: HotkeyRecorderView, didRecord hotkey: HotkeyRecorderView.Hotkey)
    func hotkeyRecorderDidCancelRecording(_ recorder: HotkeyRecorderView)
    func hotkeyRecorderDidStartRecording(_ recorder: HotkeyRecorderView)
    func hotkeyRecorderDidStopRecording(_ recorder: HotkeyRecorderView)
}

class HotkeyRecorderView: NSView {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HotkeyRecorderView")
    
    // MARK: - Hotkey Data Structure
    struct Hotkey: Equatable {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        
        var displayString: String {
            var parts: [String] = []
            
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.command) { parts.append("⌘") }
            
            // Use HotKey library's built-in key description
            if let key = Key(carbonKeyCode: keyCode) {
                parts.append(key.description)
            } else {
                parts.append("Key\(keyCode)")
            }
            
            return parts.joined()
        }
    }
    
    // MARK: - Properties
    weak var delegate: HotkeyRecorderDelegate?
    
    private var currentHotkey: Hotkey? {
        didSet {
            updateDisplay()
        }
    }
    
    private var isRecording = false {
        didSet {
            updateRecordingState()
        }
    }
    
    // UI Elements
    private let stackView = NSStackView()
    private let hotkeyField = NSTextField()
    private let recordButton = NSButton()
    
    // Event monitoring
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        // Clean up event monitors
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Configure stack view
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // Configure hotkey display field
        hotkeyField.isEditable = false
        hotkeyField.isBordered = true
        hotkeyField.bezelStyle = .roundedBezel
        hotkeyField.alignment = .center
        hotkeyField.placeholderString = "No hotkey set"
        hotkeyField.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure record button
        recordButton.title = "Record"
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to stack view
        stackView.addArrangedSubview(hotkeyField)
        stackView.addArrangedSubview(recordButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            hotkeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            recordButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        updateDisplay()
    }
    
    // MARK: - Public API
    func setHotkey(_ hotkey: Hotkey?) {
        currentHotkey = hotkey
    }
    
    func getHotkey() -> Hotkey? {
        return currentHotkey
    }
    
    // MARK: - Recording Control
    @objc private func recordButtonClicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        logger.info("Starting hotkey recording")
        
        // Notify delegate to disable global hotkey
        delegate?.hotkeyRecorderDidStartRecording(self)
        
        // Start local event monitoring (when app has focus)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.logger.info("📥 Local event: \(event.type.rawValue), keyCode: \(event.keyCode)")
            return self?.handleRecordingEvent(event)
        }
        
        // Start global event monitoring (when app doesn't have focus)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.logger.info("🌍 Global event: \(event.type.rawValue), keyCode: \(event.keyCode)")
            _ = self?.handleRecordingEvent(event)
        }
        
        logger.info("Event monitors active")
        
        // Make this view first responder to capture Escape key
        window?.makeFirstResponder(self)
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        logger.info("Recording stopped")
        delegate?.hotkeyRecorderDidStopRecording(self)
        delegate?.hotkeyRecorderDidCancelRecording(self)
    }
    
    // MARK: - Event Handling
    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        
        // Handle escape to cancel
        if event.type == .keyDown && event.keyCode == 53 { // Escape key
            stopRecording()
            return nil // Block the event
        }
        
        // Only process key down events with modifiers
        guard event.type == .keyDown else { return nil }
        
        let keyCode = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        
        // Require at least one modifier (to avoid capturing regular typing)
        guard !modifiers.isEmpty else { return nil }
        
        // Don't allow just modifier keys alone
        let isModifierKey = [55, 54, 59, 62, 58, 61, 56, 60, 63].contains(keyCode) // Cmd, Ctrl, Opt, Shift, Fn
        guard !isModifierKey else { return nil }
        
        // Create and record the hotkey
        let hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
        currentHotkey = hotkey
        isRecording = false
        
        // Clean up monitors
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        // Notify delegate
        logger.info("Recorded hotkey: \(hotkey.displayString)")
        delegate?.hotkeyRecorderDidStopRecording(self)
        delegate?.hotkeyRecorder(self, didRecord: hotkey)
        
        return nil // Block the event from being processed further
    }
    
    // MARK: - UI Updates
    private func updateDisplay() {
        if let hotkey = currentHotkey {
            hotkeyField.stringValue = hotkey.displayString
        } else {
            hotkeyField.stringValue = ""
        }
    }
    
    private func updateRecordingState() {
        if isRecording {
            recordButton.title = "Stop"
            hotkeyField.stringValue = "Press hotkey..."
            hotkeyField.textColor = .systemBlue
        } else {
            recordButton.title = "Record"
            hotkeyField.textColor = .labelColor
            updateDisplay()
        }
    }
    
    // MARK: - First Responder
    override var acceptsFirstResponder: Bool {
        return isRecording
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle escape when we're first responder
        if event.keyCode == 53 && isRecording { // Escape
            stopRecording()
        } else {
            super.keyDown(with: event)
        }
    }
}