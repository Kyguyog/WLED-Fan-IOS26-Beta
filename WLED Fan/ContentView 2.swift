import SwiftUI
import Network
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
    @State private var isFanOn: Bool = false
    @State private var fanSpeed: Double = 50

    // Light state
    @State private var isLightOn: Bool = false
    @State private var brightness: Double = 50
    @State private var lightColor: Color = .yellow

    // UI
    @State private var showingSettings = false

    // UDP connection (WLED Realtime UDP port 21324)
    private let wledUDPPort: NWEndpoint.Port = 21324
    @State private var connection: NWConnection?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Device banner / button
                HStack(spacing: 8) {
                    if let device = manager.selectedDevice {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text(device.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("(\(device.ip))")
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Text("No device selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Button("Devices") { showingSettings = true }
                }
                .padding(.horizontal)

                if mode == .simple {
                    // Simple mode controls (fan & light)
                    VStack(spacing: 20) {
                        // Fan Section
                        sectionContainer {
                            HStack {
                                Image(systemName: "fanblades.fill").foregroundStyle(.blue)
                                Text("Fan").font(.headline)
                                Spacer()
                                Toggle("", isOn: $isFanOn)
                                    .labelsHidden()
                                    .onChange(of: isFanOn) { _, on in
                                        // If toggled off, set speed to 0; if on and speed is 0, set to a default
                                        if !on { fanSpeed = 0; sendFanPWM() }
                                        else if fanSpeed == 0 { fanSpeed = 50; sendFanPWM() }
                                    }
                            }

                            HStack {
                                Slider(value: $fanSpeed, in: 0...100, step: 1) { Text("Fan Speed") } onEditingChanged: { editing in
                                    if !editing { sendFanPWM() }
                                }
                                .disabled(!isFanOn)
                                Text("\(Int(fanSpeed))%")
                                    .frame(width: 44, alignment: .trailing)
                                    .foregroundStyle(isFanOn ? .primary : .secondary)
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
                                        // On toggle, send an immediate realtime update
                                        sendLightRealtime()
                                    }
                            }

                            HStack {
                                Slider(value: $brightness, in: 0...100, step: 1) { Text("Brightness") }
                                    .disabled(!isLightOn)
                                    .onChange(of: brightness) { _, _ in
                                        // Send realtime on change (lightweight)
                                        sendLightRealtime()
                                    }
                                Text("\(Int(brightness))%")
                                    .frame(width: 44, alignment: .trailing)
                                    .foregroundStyle(isLightOn ? .primary : .secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Color")
                                ColorPicker("Color", selection: $lightColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .disabled(!isLightOn)
                                    .onChange(of: lightColor) { _, _ in
                                        sendLightRealtime()
                                    }
                            }
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    // Web mode: show WebView or placeholder
                    if let device = manager.selectedDevice, let url = URL(string: "http://\(device.ip)") {
                        WebView(url: url)
                            .edgesIgnoringSafeArea(.bottom)
                    } else {
                        Spacer()
                        Text("No WLED device selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationTitle("WLED Fan & Light")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Picker("Mode", selection: $mode) {
                        Text("Simple").tag(Mode.simple)
                        Text("Web").tag(Mode.web)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(manager: manager)
            }
            .onChange(of: manager.selectedDevice) { _, _ in
                setupUDP()
            }
            .onAppear {
                setupUDP()
            }
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
        guard isFanOn else { return }
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

    // MARK: - Light via UDP Realtime
    private func setupUDP() {
        connection?.cancel()
        connection = nil

        guard let device = manager.selectedDevice, let port = Optional(wledUDPPort) else { return }
        let host = NWEndpoint.Host(device.ip)
        let params = NWParameters.udp
        let conn = NWConnection(host: host, port: port, using: params)
        connection = conn
        conn.stateUpdateHandler = { _ in }
        conn.start(queue: .main)
    }

    private func sendLightRealtime() {
        guard let conn = connection, let _ = manager.selectedDevice else { return }
        guard isLightOn else { return }

        // Convert Color -> RGB 0...255
        let ui = UIColor(lightColor)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 0, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = UInt8(max(0, min(255, Int(r * 255))))
        let G = UInt8(max(0, min(255, Int(g * 255))))
        let B = UInt8(max(0, min(255, Int(b * 255))))

        let bri = UInt8(max(0, min(255, Int((brightness / 100.0) * 255))))

        // WLED UDP Realtime: We will send RGB at brightness by scaling; simplest: scale RGB by bri
        func scaled(_ c: UInt8) -> UInt8 {
            let v = Int(c) * Int(bri) / 255
            return UInt8(v)
        }
        let payload: [UInt8] = [scaled(R), scaled(G), scaled(B)]

        let data = Data(payload)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }
}

#Preview { ContentView() }

