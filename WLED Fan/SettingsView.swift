import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var manager: WLEDManager
    @State private var newName = ""
    @State private var newIP = ""

    var body: some View {
        NavigationView {
            Form {
                // Add Device Section
                Section(header: Text("Add New Device")) {
                    TextField("Name", text: $newName)
                    TextField("IP or Hostname", text: $newIP)
                        .keyboardType(.URL)
                    Button("Add") {
                        let newDevice = WLEDDevice(name: newName, ip: newIP)
                        if !manager.devices.contains(newDevice) {
                            manager.devices.append(newDevice)
                        }
                        newName = ""
                        newIP = ""
                    }
                }

                // Saved Devices Section
                Section(header: Text("Your Devices")) {
                    HStack {
                        Text("AP Mode")
                        Spacer()
                        if manager.selectedDevice?.ip == "4.3.2.1" {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        manager.selectedDevice = WLEDDevice(name: "AP Mode", ip: "4.3.2.1")
                    }

                    ForEach(manager.devices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            if manager.selectedDevice == device {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.selectedDevice = device
                        }
                    }
                    .onDelete { indexSet in
                        manager.devices.remove(atOffsets: indexSet)
                    }
                }

                // Discovered Devices Section with Refresh Button and Dynamic Message
                Section(header:
                    HStack {
                        Text("Discovered Devices")
                        Spacer()
                        if manager.isSearching {
                            ProgressView()
                        } else {
                            Button(action: {
                                manager.startDiscovery()
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                ) {
                    if manager.isSearching {
                        Text("Searching...")
                            .foregroundColor(.gray)
                    } else if manager.discoveredDevices.isEmpty {
                        Text("No WLED devices found")
                            .foregroundColor(.gray)
                    }

                    ForEach(manager.discoveredDevices, id: \.ip) { device in
                        Button {
                            if !manager.devices.contains(device) {
                                manager.devices.append(device)
                            }
                            manager.selectedDevice = device
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.ip)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if manager.selectedDevice == device {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                // Contact Section
                Section {
                    HStack {
                        Spacer()
                        Link("Github (Not Public, Yet)", destination: URL(string: "https://github.com/Kyguyog/RGB-Desk-Fan?tab=readme-ov-file")!)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Link("Email Me", destination: URL(string: "mailto:thaynekyan14@gmail.com")!)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}
