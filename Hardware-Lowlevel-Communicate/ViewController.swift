//
//  ViewController.swift
//  Hardware-Lowlevel-Communicate
//
//  Created by Leon on 2023/8/11.
//

import UIKit
import WebKit
import WKWebViewJavascriptBridge
import CoreBluetooth

class ViewController: UIViewController {
    var webView: WKWebView!
    var initButton: UIButton!
    var searchDeviceButton: UIButton!
    var getFeaturesButton: UIButton!
    var getBtcAddressButton: UIButton!
    var bridge: WKWebViewJavascriptBridge!
    var manager: CBCentralManager!
    var peripheral: CBPeripheral!
    var writeCharacteristic: CBCharacteristic!
    var notifyCharacteristic: CBCharacteristic!
    
    var device: Device?
    
    let ServiceID = "00000001-0000-1000-8000-00805f9b34fb"
    
    // Callbacks cache
    var searchDeviceCallback: (([[String: String]]) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        view.backgroundColor = UIColor.white
        
        manager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        manager.delegate = self
        
        setupViews()
        
        if #available(iOS 16.4, *) {
           webView.isInspectable = true
        }
        
        bridge = WKWebViewJavascriptBridge(webView: webView)
        registerBridgeHandler()
        
        // load index.html
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "web/dist") {
            let url = URL(fileURLWithPath: htmlPath)
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
    }
    
    func setupViews() {
        // WebView
        webView = WKWebView(frame: CGRect(x: 0, y: UIScreen.main.bounds.height - 200, width: UIScreen.main.bounds.width, height: 100))
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        // init button
        initButton = UIButton.init(frame: CGRect(x: 0, y: 84, width: UIScreen.main.bounds.width, height: 30))
        initButton.translatesAutoresizingMaskIntoConstraints = false
        initButton.setTitle("Initialize SDK", for: .normal)
        initButton.setTitleColor(UIColor.blue, for: .normal)
        initButton.setTitleColor(UIColor.gray, for: .highlighted)
        initButton.addTarget(self, action: #selector(onInitializeSDK), for: .touchUpInside)
        view.addSubview(initButton)
        
        // search device button
        searchDeviceButton = UIButton.init(frame: CGRect(x: 0, y: 114, width: UIScreen.main.bounds.width, height: 30))
        searchDeviceButton.translatesAutoresizingMaskIntoConstraints = false
        searchDeviceButton.setTitle("Search Device", for: .normal)
        searchDeviceButton.setTitleColor(UIColor.blue, for: .normal)
        searchDeviceButton.setTitleColor(UIColor.gray, for: .highlighted)
        searchDeviceButton.addTarget(self, action: #selector(onSearch), for: .touchUpInside)
        view.addSubview(searchDeviceButton)
        
        // getFetaures button
        getFeaturesButton = UIButton.init(frame: CGRect(x: 0, y: 144, width: UIScreen.main.bounds.width, height: 30))
        getFeaturesButton.translatesAutoresizingMaskIntoConstraints = false
        getFeaturesButton.setTitle("Get Features", for: .normal)
        getFeaturesButton.setTitleColor(UIColor.blue, for: .normal)
        getFeaturesButton.setTitleColor(UIColor.gray, for: .highlighted)
        getFeaturesButton.addTarget(self, action: #selector(onGetFeatures), for: .touchUpInside)
        view.addSubview(getFeaturesButton)
        
        // getBtcAddress button
        getBtcAddressButton = UIButton.init(frame: CGRect(x: 0, y: 174, width: UIScreen.main.bounds.width, height: 30))
        getBtcAddressButton.translatesAutoresizingMaskIntoConstraints = false
        getBtcAddressButton.setTitle("Get Bitcoin Address", for: .normal)
        getBtcAddressButton.setTitleColor(UIColor.blue, for: .normal)
        getBtcAddressButton.setTitleColor(UIColor.gray, for: .highlighted)
        getBtcAddressButton.addTarget(self, action: #selector(onGetBitcoinAddress), for: .touchUpInside)
        view.addSubview(getBtcAddressButton)
        
    }
    
    @objc func onInitializeSDK() {
        print("🔵 onInitializeSDK called")
       bridge.call(handlerName: "init", data: [1, 2, 3]) { (responseData) in
            print("init result: ", responseData ?? "")
        }
    }
    
    @objc func onSearch() {
        print("🔵 onSearch called")
        bridge.call(handlerName: "bridgeCommonCall", data: ["name": "searchDevices", "data": [
            "connectId": "",
            "deviceId": ""
        ]]) { responseData in
            print("🔵 searchDevice callback received with result:", responseData ?? "nil")
        }
    }
    
    func registerBridgeHandler() {
        print("=== Starting to register bridge handlers ===")
        
        // enumerate
        bridge.register(handlerName: "enumerate") { parameters, callback in
            print("🔵 enumerate called with parameters:", parameters ?? "nil")
            self.manager.scanForPeripherals(withServices: [CBUUID(string: self.ServiceID)], options: nil)
            print("🔵 Started scanning for peripherals with ServiceID:", self.ServiceID)
            
            if let peripheral = self.peripheral {
                if (peripheral.identifier.uuidString.count > 0) {
                    print("🔵 Found existing peripheral:", peripheral.name ?? "unnamed", "id:", peripheral.identifier.uuidString)
                    callback?([["name": self.peripheral.name!, "id": self.peripheral.identifier.uuidString]])
                }
            }
            
            if let _callback = callback {
                print("🔵 Storing search device callback")
                self.searchDeviceCallback = _callback
            } else {
                print("⚠️ No callback provided for enumerate")
            }
        }
        
        // connect
        bridge.register(handlerName: "connect") { _, callback in
            self.manager.connect(self.peripheral)
                callback?(["success": true])
        }
        
        // disconnect
        bridge.register(handlerName: "disconnect") { _, callback in
            self.manager.cancelPeripheralConnection(self.peripheral)
                callback?(["success": true])
        }
        
        // send
        bridge.register(handlerName: "send") { params, callback in
            print("called send method: ", params ?? "")
            if let data = params?["data"] {
                print("🔵 Sending data:", data)
                self.peripheral.writeValue((data as! String).hexData, for: self.writeCharacteristic, type: .withoutResponse)
                callback?(["success": true])

            }
        }
        
        // receive
//        bridge.register(handlerName: "receive") { _, callback in
//            callback?(["success": true])
//        }
   
    }
    
    @objc func onGetFeatures() {
        print("🔵 onGetFeatures called")
        let data: [String: Any] = [
            "name": "getFeatures",
            "data": [
                "connectId": self.device?.getConnectId() ?? "",
                "deviceId": self.device?.getDeviceId() ?? "",
            ]
        ]
        
        bridge.call(handlerName:"bridgeCommonCall", data: data) { responseData in
            print("getFeatures response: ", responseData ?? "")
            if let responseDictionary = responseData as? [String: Any] {
                if let success = responseDictionary["success"] as? Int,
                   success == 1,
                   let payload = responseDictionary["payload"] as? [String: Any],
                   let deviceId = payload["device_id"] as? String {
                    self.device = Device(connectId: self.device?.getConnectId() ?? self.peripheral.identifier.uuidString, deviceId: deviceId)
                    print("✅ Device updated - connectId:", self.device?.getConnectId() ?? "", "deviceId:", self.device?.getDeviceId() ?? "")
                } else {
                    print("⚠️ Invalid response format or unsuccessful response")
                }
            } else {
                print("⚠️ Could not parse response as dictionary")
            }
        }
    }
    
    @objc func onGetBitcoinAddress() {

    bridge.call(handlerName: "bridgeCommonCall", data: [
            "name": "btcGetAddress",
            "data": [
                "connectId": self.device?.getConnectId() ?? "",
                "deviceId": self.device?.getDeviceId() ?? "",
                "path": "m/49'/0'/0'/0/0",
                "coin": "btc",
                "showOnOneKey": true
            ]
        ] as [String : Any]) { response in
            print("get bitcoin address response: ", response ?? "")
        }
    }
}

//MARK:- CBCentralManagerDelegate
extension ViewController: CBCentralManagerDelegate {
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("🔵 Bluetooth state updated:", central.state.rawValue)
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on and ready")
        case .poweredOff:
            print("⚠️ Bluetooth is powered off")
        case .unauthorized:
            print("⚠️ Bluetooth is unauthorized")
        case .unsupported:
            print("⚠️ Bluetooth is unsupported")
        case .resetting:
            print("⚠️ Bluetooth is resetting")
        default:
            print("⚠️ Bluetooth is in unknown state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // print("🔵 Discovered peripheral:", peripheral.name ?? "unnamed")
        // print("🔵 Advertisement data:", advertisementData)
        // print("🔵 RSSI:", RSSI)
        
        self.peripheral = peripheral
        print("✅ Stored peripheral reference")
        
        if let callback = searchDeviceCallback {
            print("🔵 Calling search device callback")
            callback([["name": peripheral.name!, "id": peripheral.identifier.uuidString]])
        } else {
            print("⚠️ No search device callback available")
        }
        
        manager.stopScan()
        print("✅ Stopped scanning")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
      //discover all service
      peripheral.discoverServices(nil)
      peripheral.delegate = self
    }
}

//MARK:- CBPeripheralDelegate
extension ViewController : CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let services = peripheral.services {
            
            //discover characteristics of services
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        let writeUuid = CBUUID(string: "00000002-0000-1000-8000-00805f9b34fb")
        let notifyUuid = CBUUID(string: "00000003-0000-1000-8000-00805f9b34fb")
        var setWriteC = false
        var setNotifyC = false
        
        if let charac = service.characteristics {
            for characteristic in charac {
                //MARK:- Light Value
                if characteristic.uuid == writeUuid {
                    print("set writeCharacteristic")
                    self.writeCharacteristic = characteristic
                    setWriteC = true
                }
                if characteristic.uuid == notifyUuid {
                    print("set notifyCharacteristic")
                    self.notifyCharacteristic = characteristic
                    self.peripheral.setNotifyValue(true, for: self.notifyCharacteristic)
                    setNotifyC = true
                }
            }
            if (setWriteC && setNotifyC) {
                print("Set Characteristic Success")
                bridge.call(handlerName: "connectFinished", data: nil)
            }
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            // 处理错误情况
            print("characteristic monitor error: ", error ?? "")
            return
        }
        
        if characteristic.uuid == self.notifyCharacteristic.uuid {
            if let value = characteristic.value {
                let receivedData = value
                print("received data: -> : ", receivedData.hexString)
                bridge.call(handlerName: "monitorCharacteristic", data: receivedData.hexString)
            }
        }
    }
}

class Device {
    var connectId: String
    var deviceId: String
    
    init(connectId: String, deviceId: String) {
        self.connectId = connectId
        self.deviceId = deviceId
    }
    
    func getConnectId() -> String {
        return self.connectId
    }
    
    func getDeviceId() -> String {
        return self.deviceId
    }
}
