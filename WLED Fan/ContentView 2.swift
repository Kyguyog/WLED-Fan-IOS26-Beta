import SwiftUI
import WebKit

enum Mode: String, CaseIterable, Identifiable {
    case simple = "Simple"
    case web = "Web"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var manager = WLEDManager()
    
    @State private var mode: Mode = .simple

    // Fan state
    @State private var fanSpeed: Double = 50

    // Light state
    @State private var isLightOn: Bool = false
    @State private var brightness: Double = 50
    @State private var isEditingBrightness: Bool = false
    @State private var pollTimer: Timer? = nil

    // Presets
    @State private var presets: [WLEDPre] = []
    @State private var activePresetID: Int? = nil

    // UI
    @State private var showingSettings = false
    
    @State private var lightDebounceWorkItem: DispatchWorkItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if mode == .simple {
                    // Simple mode controls (fan & light)
                    VStack(spacing: 20) {
                        // Fan Section
                        sectionContainer {
                            HStack {
                                Image(systemName: "fanblades.fill").foregroundStyle(.blue)
                                Text("Fan").font(.headline)
                                Spacer()
                            }

                            HStack {
                                Slider(value: $fanSpeed, in: 0...100, step: 1) { Text("Fan Speed") } onEditingChanged: { editing in
                                    if !editing { sendFanPWM() }
                                }
                                Text("\(Int(fanSpeed))%")
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        // Light Section
                        sectionContainer {
                            HStack {
                                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                                Text("Light").font(.headline)
                                Spacer()
                                Toggle("", isOn: $isLightOn)
                                    .labelsHidden()
                                    .onChange(of: isLightOn) { _, _ in
                                        // On toggle, send an immediate persistent update
                                        sendLightState()
                                    }
                            }

                            HStack {
                                Slider(value: $brightness, in: 0...100, step: 1) { Text("Brightness") } onEditingChanged: { editing in
                                    isEditingBrightness = editing
                                    if !editing { sendLightState() }
                                }
                                .onChange(of: brightness) { _, _ in
                                    scheduleDebouncedLightSend()
                                }
                                Text("\(Int(brightness))%")
                                    .frame(width: 44, alignment: .trailing)
                                    .foregroundStyle(.primary)
                            }
                        }

                        sectionContainer {
                            HStack {
                                Image(systemName: "star.fill").foregroundStyle(.orange)
                                Text("Presets").font(.headline)
                                Spacer()
                                Button(action: { fetchPresets() }) {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .accessibilityLabel("Refresh Presets")
                            }

                            if presets.isEmpty {
                                Text("No presets available").foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(presets, id: \._id) { p in
                                            Button(action: { applyPreset(p._id) }) {
                                                Text(p.name)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill((activePresetID == p._id) ? Color.accentColor.opacity(0.35) : Color.accentColor.opacity(0.15))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke((activePresetID == p._id) ? Color.accentColor : Color.clear, lineWidth: 2)
                                                    )
                                                    .foregroundStyle((activePresetID == p._id) ? Color.accentColor : Color.primary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .onAppear {
                        fetchPresets()
                        fetchActivePreset()
                    }
                } else {
                    // Web mode: show WebView or placeholder
                    if let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)") {
                        WebView(url: url)
                            .ignoresSafeArea()
                    } else {
                        Spacer()
                        Text("No WLED device selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            //.navigationTitle("WLED Fan & Light")
            //.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button(action: { showingSettings = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.connected.to.line.below")
                                Text("Devices")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Picker("Mode", selection: $mode) {
                            Text("Simple").tag(Mode.simple)
                            Text("Web").tag(Mode.web)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(manager: manager)
            }
            .onChange(of: manager.selectedDevice) { _ in
                fetchPresets()
                fetchActivePreset()
                fetchBrightness()
            }
            .onAppear { startBrightnessPolling() }
            .onDisappear { stopBrightnessPolling() }
        }
    }

    // MARK: - Section styling helper
    @ViewBuilder
    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Fan via HTTP JSON
    private func sendFanPWM() {
        guard let device = manager.selectedDevice else { return }
        guard let url = URL(string: "http://\(device.ip)/json") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData: [String: Any] = [
            "PWM-fan": [
                "speed": Int(fanSpeed),
                "lock": true
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonData)
        } catch { return }

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Light via HTTP JSON (persistent)
    private func sendLightState() {
        guard let device = manager.selectedDevice else { return }
        guard let url = URL(string: "http://\(device.ip)/json/state") else { return }

        let bri = max(0, min(255, Int((brightness / 100.0) * 255)))

        var body: [String: Any] = [
            "on": isLightOn,
            "bri": bri
        ]

        // If turned off, optionally set brightness to 0 to ensure off
        if !isLightOn { body["bri"] = 0 }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch { return }

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func scheduleDebouncedLightSend() {
        lightDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [isLightOn, brightness] in
            sendLightState()
        }
        lightDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Brightness Polling
    private func startBrightnessPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isEditingBrightness else { return }
            fetchBrightness()
        }
    }

    private func stopBrightnessPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchBrightness() {
        guard let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)/json/state") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bri = json["bri"] as? Int else { return }
            let sliderValue = max(0, min(100, Int((Double(bri) / 255.0) * 100.0)))
            DispatchQueue.main.async {
                self.brightness = Double(sliderValue)
                self.isLightOn = (bri > 0) // keep toggle roughly in sync
            }
        }.resume()
    }

    struct WLEDPre: Decodable {
        let _id: Int
        let name: String
    }

    private func fetchPresets() {
        guard let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)/presets.json") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            // presets.json is typically a dictionary of id->object. We'll try to decode into a map then map to array.
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var items: [WLEDPre] = []
                for (key, value) in dict {
                    if let id = Int(key), let obj = value as? [String: Any], let name = obj["n"] as? String {
                        items.append(WLEDPre(_id: id, name: name))
                    }
                }
                let sorted = items.sorted { $0._id < $1._id }
                DispatchQueue.main.async { self.presets = sorted }
            }
        }.resume()
    }
    
    private func fetchActivePreset() {
        guard let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)/json/state") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let ps = json["ps"] as? Int
                DispatchQueue.main.async { self.activePresetID = ps }
            }
        }.resume()
    }

    private func applyPreset(_ id: Int) {
        self.activePresetID = id
        guard let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)/json/state") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["ps": id]
        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { return }
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Re-fetch to confirm active preset
            fetchActivePreset()
        }.resume()
    }
}

#Preview { ContentView() }

