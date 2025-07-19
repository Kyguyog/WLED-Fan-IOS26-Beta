import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WLEDManager()
    @State private var fanSpeed: Double = 100
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Expand to fill all available space above the controls
            Group {
                if let device = manager.selectedDevice,
                   let url = URL(string: "http://\(device.ip)") {
                    WebView(url: url)
                } else {
                    Text("No WLED device selected.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .clipped()

            Divider()

            VStack(spacing: 12) {
                HStack {
                    Text("PWM Fan: \(Int(fanSpeed))")
                    Spacer()
                    Button("Devices") {
                        showingSettings = true
                    }
                }

                Slider(value: $fanSpeed, in: 0...100, step: 1) {
                    Text("Fan Speed")
                } onEditingChanged: { editing in
                    if !editing {
                        sendPWM()
                    }
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(manager: manager)
        }
    }
    
    // FIXED: Updated to use JSON API for PWM fan usermod
    func sendPWM() {
        guard let device = manager.selectedDevice else { return }
        guard let url = URL(string: "http://\(device.ip)/json") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonData: [String: Any] = [
            "PWM-fan": [
                "speed": Int(fanSpeed),
                "lock": true  // Lock the fan at this speed
            ]
        ]
        
        do {
            let jsonBody = try JSONSerialization.data(withJSONObject: jsonData)
            request.httpBody = jsonBody
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error sending PWM command: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("PWM command sent, status: \(httpResponse.statusCode)")
                }
            }.resume()
            
        } catch {
            print("Error creating JSON: \(error)")
        }
    }
}
