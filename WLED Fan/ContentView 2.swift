import SwiftUI

struct ContentView: View {
    @State private var isFanOn: Bool = false
    @State private var fanSpeed: Double = 50
    @State private var isLightOn: Bool = false
    @State private var brightness: Double = 50
    @State private var lightColor: Color = .yellow

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Fan Section
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "fanblades.fill")
                            .foregroundColor(.blue)
                        Text("Fan")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $isFanOn)
                            .labelsHidden()
                    }
                    HStack {
                        Slider(value: $fanSpeed, in: 0...100)
                            .disabled(!isFanOn)
                        Text("\(Int(fanSpeed))%")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundColor(isFanOn ? .primary : .secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                // Light Section
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Light")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $isLightOn)
                            .labelsHidden()
                    }
                    HStack {
                        Slider(value: $brightness, in: 0...100)
                            .disabled(!isLightOn)
                        Text("\(Int(brightness))%")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundColor(isLightOn ? .primary : .secondary)
                    }
                    ColorPicker("Color", selection: $lightColor)
                        .disabled(!isLightOn)
                        .labelsHidden(false)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)

                Spacer()
            }
            .padding()
            .navigationTitle("WLED Fan & Light")
        }
    }
}

#Preview {
    ContentView()
}
