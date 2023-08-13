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
    
    var buffer = Data()
    var bufferLength: UInt32 = UInt32(0)
    
    // Callbacks cache
    var searchDeviceCallback: (([[String: String]]) -> Void)?
    var receiveCallback: ((String) -> Void)?
    
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
        bridge.call(handlerName: "init", data: [1, 2, 3]) { (responseData) in
            print("init result: ", responseData ?? "")
        }
    }
    
    @objc func onSearch() {
        bridge.call(handlerName: "searchDevice", data: nil, callback: {(responseData) in
            print("searchDevice result ===>>>: ", responseData ?? "")
            if let responseDictionary = responseData as? [String: Any],
               let success = responseDictionary["success"] as? Int,
               success == 1,
               let payload = responseDictionary["payload"] as? [Any],
               let device = payload.first,
               let deviceDictionary = device as? [String: Any],
               let connectId = deviceDictionary["connectId"] as? String,
               let deviceId = deviceDictionary["deviceId"] as? String {
                   print(connectId, deviceId)
                   self.device = Device(connectId: connectId, deviceId: deviceId)
                   return
            }
        })
    }
    
    func registerBridgeHandler() {
        // enumerate
        bridge.register(handlerName: "enumerate") { parameters, callback in
            print("plugin call enumerate")
            self.manager.scanForPeripherals(withServices: [CBUUID(string: self.ServiceID)], options: nil)
            if let peripheral = self.peripheral {
                if (peripheral.identifier.uuidString.count > 0) {
                    callback?([["name": self.peripheral.name!, "id": self.peripheral.identifier.uuidString]])
                }
            }
            
            if let _callback = callback {
                self.searchDeviceCallback = _callback
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
                self.peripheral.writeValue((data as! String).hexData, for: self.writeCharacteristic, type: .withoutResponse)
                callback?(["success": true])

            }
        }
        
        // receive
        bridge.register(handlerName: "receive") { _, callback in
            if let _callback = callback {
                self.receiveCallback = _callback
            }
        }
   
    }
    
    @objc func onGetFeatures() {
        bridge.call(handlerName: "getFeatures", data: ["connectId": self.device?.getConnectId()]) { responseData in
            print("getFeatures response: ", responseData ?? "")
        }
    }
    
    @objc func onGetBitcoinAddress() {
        bridge.call(handlerName: "btcGetAddress", data: [
            "connectId": self.device?.getConnectId() ?? "",
            "deviceId": self.device?.getDeviceId() ?? "",
            "path": "m/49'/0'/0'/0/0",
            "coin": "btc",
            "showOnOneKey": true
        ] as [String : Any]) { response in
            print("get bitcoin address response: ", response ?? "")
        }
    }

}

//MARK:- CBCentralManagerDelegate
extension ViewController: CBCentralManagerDelegate {
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("====> Bluetooth powerdOn")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // 处理发现的设备，例如，将设备信息存储到数组中
        self.peripheral = peripheral
        print("peripheral ===> : ", peripheral.name, peripheral.identifier.uuidString)
        
        searchDeviceCallback?([["name": peripheral.name!, "id": peripheral.identifier.uuidString]])
        
        manager.stopScan()
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
                
                // 分析是否是第首包数据
                if (isHeaderChunk(chunk: receivedData)) {
                    print("isHeaderChunk: ", true)
                    // 读取完整数据包长度
                    bufferLength = receivedData.subdata(in: 5..<9).withUnsafeBytes { rawBuffer in
                        rawBuffer.load(as: UInt32.self).bigEndian
                    }
                    print("bufferLength: ", bufferLength)
                    
                    // 移除协议中的 magic 字符后，拼接 buffer
                    buffer = receivedData.subdata(in: 3..<receivedData.count)
                } else {
                    // 非首包数据直接拼接 buffer
                    buffer.append(receivedData)
                }
                // 数据包长度接收完整后返回数据
                if (buffer.count - COMMON_HEADER_SIZE >= bufferLength) {
                    print("Received result ==> ", buffer.hexString)
                    receiveCallback?(buffer.hexString)
                }
            }
        }
    }
}

let COMMON_HEADER_SIZE = 6;
let MESSAGE_TOP_CHAR: UInt8 = 63
let MESSAGE_HEADER_BYTE: UInt8 = 35
func isHeaderChunk(chunk: Data) -> Bool {
    guard chunk.count >= 9 else {
        return false
    }
    
    let magicQuestionMark = Int(chunk[0])
    let sharp1 = Int(chunk[1])
    let sharp2 = Int(chunk[2])
    
    if
        String(UnicodeScalar(magicQuestionMark)!) == String(UnicodeScalar(MESSAGE_TOP_CHAR)) &&
        String(UnicodeScalar(sharp1)!) == String(UnicodeScalar(MESSAGE_HEADER_BYTE)) &&
        String(UnicodeScalar(sharp2)!) == String(UnicodeScalar(MESSAGE_HEADER_BYTE))
    {
        return true
    }
    
    return false
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
