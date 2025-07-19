import Foundation
import Network

struct WLEDDevice: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ip: String

    static func == (lhs: WLEDDevice, rhs: WLEDDevice) -> Bool {
        lhs.ip == rhs.ip
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ip)
    }
}

class WLEDManager: NSObject, ObservableObject {
    @Published var devices: [WLEDDevice] {
        didSet {
            save()
        }
    }

    @Published var selectedDevice: WLEDDevice? {
        didSet {
            save()
        }
    }

    @Published var discoveredDevices: [WLEDDevice] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    private var serviceBrowser: NetServiceBrowser?
    private var refreshTimer: Timer?
    private var activeResolves: [NetService] = []

    override init() {
        self.devices = []
        super.init()

        if let data = UserDefaults.standard.data(forKey: "wled_devices"),
           let decoded = try? JSONDecoder().decode([WLEDDevice].self, from: data) {
            self.devices = decoded
        }

        if let selectedID = UserDefaults.standard.string(forKey: "selected_device_id"),
           let device = devices.first(where: { $0.id.uuidString == selectedID }) {
            selectedDevice = device
        }

        startDiscovery()
        startDiscoveryTimer()
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "wled_devices")
        }

        if let selected = selectedDevice {
            UserDefaults.standard.set(selected.id.uuidString, forKey: "selected_device_id")
        }
    }

    func startDiscovery() {
        print("🔍 Starting WLED discovery...")
        isSearching = true
        discoveredDevices.removeAll()
        errorMessage = nil
        activeResolves.removeAll()

        serviceBrowser?.stop()
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
        serviceBrowser?.searchForServices(ofType: "_wled._tcp.", inDomain: "local.")

    }

    func startDiscoveryTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.startDiscovery()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        serviceBrowser?.stop()
    }
}

extension WLEDManager: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("🌐 Found service: \(service.name)")
        service.delegate = self
        activeResolves.append(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("✅ Discovery finished.")
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("❌ Discovery failed: \(errorDict)")
        DispatchQueue.main.async {
            self.errorMessage = "Discovery failed: \(errorDict)"
            self.isSearching = false
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("❌ Failed to resolve: \(sender.name) - \(errorDict)")
        activeResolves.removeAll { $0 == sender }
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        defer {
            activeResolves.removeAll { $0 == service }
        }

        guard let ip = getIP(from: service) else {
            print("⚠️ Could not resolve IP for service: \(service.name)")
            return
        }

        print("✅ Resolved IP: \(ip) for \(service.name)")
        let newDevice = WLEDDevice(name: service.name, ip: ip)

        DispatchQueue.main.async {
            if !self.devices.contains(newDevice) && !self.discoveredDevices.contains(newDevice) {
                print("➕ Discovered new WLED device: \(newDevice.name) @ \(newDevice.ip)")
                self.discoveredDevices.append(newDevice)
            }
        }
    }

    private func getIP(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }

        for addressData in addresses {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = addressData.withUnsafeBytes { pointer -> Int32 in
                let sockaddrPtr = pointer.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                return getnameinfo(
                    sockaddrPtr,
                    socklen_t(addressData.count),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }

            if result == 0 {
                let ip = String(cString: hostname)
                if ip != "127.0.0.1" && !ip.isEmpty {
                    return ip
                }
            }
        }

        print("❌ Failed to resolve a usable IP address.")
        return nil
    }
}
