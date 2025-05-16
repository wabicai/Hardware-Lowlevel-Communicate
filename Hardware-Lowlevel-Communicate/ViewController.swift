//
//  ViewController.swift
//  Hardware-Lowlevel-Communicate
//
//  Created by Leon on 2023/8/11.
//

import CoreBluetooth
import UIKit
import WKWebViewJavascriptBridge
import WebKit

// UserDefaults keys
let kLastConnectedDeviceId = "lastConnectedDeviceId"
let kLastConnectedDeviceName = "lastConnectedDeviceName"

class ViewController: UIViewController {
    var webView: WKWebView!
    var initButton: UIButton!
    var searchDeviceButton: UIButton!
    var getFeaturesButton: UIButton!
    var getBtcAddressButton: UIButton!
    var getEvmAddressButton: UIButton!  // New button for EVM Address
    var checkFirmwareButton: UIButton!  // New button for firmware check
    var checkBleFirmwareButton: UIButton!  // New button for BLE firmware check
    var bridge: WKWebViewJavascriptBridge!
    var manager: CBCentralManager!
    var peripheral: CBPeripheral!
    var writeCharacteristic: CBCharacteristic!
    var notifyCharacteristic: CBCharacteristic!
    var resultTextView: UITextView!  // 添加响应结果显示控件

    var device: Device?
    var statusLabel: UILabel!  // Status label to show connected device

    // Array to store scanned devices
    var scannedDevices: [[String: String]] = []

    let serviceID = "00000001-0000-1000-8000-00805f9b34fb"

    // Callbacks cache
    var searchDeviceCallback: (([[String: String]]) -> Void)?

    // 添加loading状态属性
    var isSearching = false

    // 添加设备列表累积变量
    var accumulatedDevices: [[String: String]] = []
    var enumerateCallback: ((Any?) -> Void)?
    var isAccumulatingDevices = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        view.backgroundColor = UIColor.white

        manager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        manager.delegate = self

        setupViews()
        loadLastConnectedDevice()

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        bridge = WKWebViewJavascriptBridge(webView: webView)
        registerBridgeHandler()

        // load index.html
        if let htmlPath = Bundle.main.path(
            forResource: "index", ofType: "html", inDirectory: "web/dist")
        {
            let url = URL(fileURLWithPath: htmlPath)
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func setupViews() {
        view.backgroundColor = UIColor.white

        // 创建一个滚动视图来容纳所有控件
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // 创建一个容器视图放在滚动视图中
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(containerView)

        // 设置滚动视图的约束
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -150),  // 给WebView留出空间

            containerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // Status Label
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.text = "No device connected"
        statusLabel.textColor = UIColor.darkGray
        containerView.addSubview(statusLabel)

        // 设置按钮
        setupButtons(in: containerView)

        // 添加结果显示区域
        resultTextView = UITextView()
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        resultTextView.isEditable = false
        resultTextView.font = UIFont.systemFont(ofSize: 14)
        resultTextView.layer.borderWidth = 1
        resultTextView.layer.borderColor = UIColor.lightGray.cgColor
        resultTextView.layer.cornerRadius = 5
        containerView.addSubview(resultTextView)

        // WebView在滚动视图外部
        webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // 设置状态标签的约束
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -20),
            statusLabel.heightAnchor.constraint(equalToConstant: 30),
        ])

        // 设置结果显示区域的约束
        NSLayoutConstraint.activate([
            resultTextView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 500),  // 放在所有按钮下面
            resultTextView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 20),
            resultTextView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -20),
            resultTextView.heightAnchor.constraint(equalToConstant: 200),
            // 设置底部约束，确保内容能完全滚动
            resultTextView.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor, constant: -20),
        ])

        // 设置WebView的约束
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.heightAnchor.constraint(equalToConstant: 150),
        ])
    }

    func setupButtons(in containerView: UIView) {
        // 创建所有按钮，直接初始化为非可选类型
        // 移除Initialize SDK按钮
        searchDeviceButton = UIButton(type: .system)
        getFeaturesButton = UIButton(type: .system)
        getBtcAddressButton = UIButton(type: .system)
        getEvmAddressButton = UIButton(type: .system)
        checkFirmwareButton = UIButton(type: .system)
        checkBleFirmwareButton = UIButton(type: .system)

        // 设置按钮样式和目标动作 - 移除Initialize SDK按钮
        let buttons: [(UIButton, String, Selector)] = [
            (searchDeviceButton, "Search Device", #selector(onSearch)),
            (getFeaturesButton, "Get Features", #selector(onGetFeatures)),
            (getBtcAddressButton, "Get Bitcoin Address", #selector(onGetBitcoinAddress)),
            (getEvmAddressButton, "Get EVM Address", #selector(onGetEvmAddress)),
            (checkFirmwareButton, "Check Firmware Release", #selector(onCheckFirmwareRelease)),
            (
                checkBleFirmwareButton, "Check BLE Firmware Release",
                #selector(onCheckBleFirmwareRelease)
            ),
        ]

        // 配置每个按钮
        for (index, (button, title, action)) in buttons.enumerated() {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(title, for: .normal)
            button.setTitleColor(UIColor.white, for: .normal)
            button.backgroundColor = UIColor.systemBlue
            button.layer.cornerRadius = 8
            button.addTarget(self, action: action, for: .touchUpInside)
            containerView.addSubview(button)

            // 设置按钮约束
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
                button.trailingAnchor.constraint(
                    equalTo: containerView.trailingAnchor, constant: -20),
                button.heightAnchor.constraint(equalToConstant: 50),
            ])

            // 第一个按钮在状态标签下面，其他按钮在前一个按钮下面
            if index == 0 {
                button.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20)
                    .isActive = true
            } else {
                button.topAnchor.constraint(
                    equalTo: buttons[index - 1].0.bottomAnchor, constant: 15
                ).isActive = true
            }
        }
    }

    // Load the last connected device from UserDefaults
    func loadLastConnectedDevice() {
        let defaults = UserDefaults.standard
        if let connectId = defaults.string(forKey: kLastConnectedDeviceId),
            let deviceName = defaults.string(forKey: kLastConnectedDeviceName)
        {
            device = Device(connectId: connectId, deviceId: "")
            statusLabel.text = "Last connected: \(deviceName)"
            print("✅ Loaded cached device - connectId: \(connectId)")
        }
    }

    // Save the connected device to UserDefaults
    func saveConnectedDevice(connectId: String, name: String) {
        let defaults = UserDefaults.standard
        defaults.set(connectId, forKey: kLastConnectedDeviceId)
        defaults.set(name, forKey: kLastConnectedDeviceName)
        defaults.synchronize()
        print("✅ Saved device to cache - connectId: \(connectId), name: \(name)")
    }

    @objc func onSearch() {
        // 如果已经在搜索中，则不重复执行
        if isSearching {
            return
        }

        // 设置搜索状态
        isSearching = true

        print("🔵 onSearch called")
        // 清空之前扫描到的设备
        scannedDevices = []
        // 清空累积的设备列表
        accumulatedDevices = []

        // 显示搜索状态
        statusLabel.text = "Scanning for devices..."
        searchDeviceButton.setTitle("Scanning...", for: .normal)
        searchDeviceButton.isEnabled = false

        // 开始扫描过程
        self.isAccumulatingDevices = true

        // 通过原生API开始扫描
        self.manager.scanForPeripherals(
            withServices: [CBUUID(string: self.serviceID)], options: nil)

        // 设置超时，停止扫描并显示结果
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.manager.stopScan()
            self.isSearching = false
            self.isAccumulatingDevices = false
            self.searchDeviceButton.setTitle("Search Device", for: .normal)
            self.searchDeviceButton.isEnabled = true

            // 如果有累积的设备，显示设备选择对话框
            if !self.accumulatedDevices.isEmpty {
                self.scannedDevices = self.accumulatedDevices
                self.showDeviceSelectionDialog()
            } else {
                // 没有找到设备
                let alert = UIAlertController(
                    title: "No Devices Found",
                    message: "Please make sure your device is powered on and nearby.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                self.statusLabel.text = "No devices found"
            }

            // 如果有未完成的回调，一次性返回所有设备
            if let callback = self.enumerateCallback {
                callback(self.accumulatedDevices)
                self.enumerateCallback = nil
            }
        }
    }

    func showDeviceSelectionDialog() {
        // If no devices found, show error
        if scannedDevices.isEmpty {
            let alert = UIAlertController(
                title: "No Devices Found",
                message: "Please make sure your device is powered on and nearby.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            statusLabel.text = "No devices found"
            return
        }

        // Create a custom alert view as an overlay
        let overlayView = UIView(frame: self.view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.tag = 1001  // Tag for removal later

        // Create alert container
        let alertWidth: CGFloat = min(self.view.bounds.width - 40, 300)
        let alertHeight: CGFloat = min(CGFloat(scannedDevices.count * 44) + 100, 300)

        let alertContainer = UIView(
            frame: CGRect(
                x: (self.view.bounds.width - alertWidth) / 2,
                y: (self.view.bounds.height - alertHeight) / 2,
                width: alertWidth,
                height: alertHeight
            ))
        alertContainer.backgroundColor = UIColor.white
        alertContainer.layer.cornerRadius = 10

        // Title label
        let titleLabel = UILabel(frame: CGRect(x: 15, y: 15, width: alertWidth - 30, height: 30))
        titleLabel.text = "Select a Device"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        alertContainer.addSubview(titleLabel)

        // Table view for devices
        let tableView = UITableView(
            frame: CGRect(
                x: 10,
                y: 50,
                width: alertWidth - 20,
                height: alertHeight - 100
            ))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DeviceCell")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.layer.cornerRadius = 5
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.3).cgColor
        alertContainer.addSubview(tableView)

        // Cancel button
        let cancelButton = UIButton(
            frame: CGRect(
                x: 10,
                y: alertHeight - 40,
                width: alertWidth - 20,
                height: 30
            ))
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor.white, for: .normal)
        cancelButton.backgroundColor = UIColor.systemBlue
        cancelButton.layer.cornerRadius = 5
        cancelButton.addTarget(self, action: #selector(dismissDeviceDialog), for: .touchUpInside)
        alertContainer.addSubview(cancelButton)

        // Add to view
        overlayView.addSubview(alertContainer)
        self.view.addSubview(overlayView)

        // Add tap gesture to dismiss when tapping outside
        let tapGesture = UITapGestureRecognizer(
            target: self, action: #selector(dismissDeviceDialog))
        tapGesture.delegate = self
        overlayView.addGestureRecognizer(tapGesture)
    }

    @objc func dismissDeviceDialog() {
        if let overlayView = self.view.viewWithTag(1001) {
            overlayView.removeFromSuperview()
        }
        statusLabel.text = "Scanning canceled"
    }

    // Handle device selection from the table
    func selectDeviceFromTable(at indexPath: IndexPath) {
        if indexPath.row < scannedDevices.count {
            let device = scannedDevices[indexPath.row]
            let deviceName = device["name"] ?? "Unnamed Device"
            let deviceId = device["id"] ?? ""

            // Dismiss the overlay view
            if let overlayView = self.view.viewWithTag(1001) {
                overlayView.removeFromSuperview()
            }

            // Then select the device
            selectDevice(deviceId: deviceId, deviceName: deviceName)
        }
    }

    func selectDevice(deviceId: String, deviceName: String) {
        // Update device and save to cache
        self.device = Device(connectId: deviceId, deviceId: "")
        self.saveConnectedDevice(connectId: deviceId, name: deviceName)
        self.statusLabel.text = "Connected: \(deviceName)"

        print("✅ Selected device - connectId: \(deviceId), name: \(deviceName)")

        // 清除搜索回调，防止继续接收搜索结果
        self.searchDeviceCallback = nil
        // 停止原生扫描（如果有的话）
        self.manager.stopScan()

        // 连接到设备 - 使用searchDevices方法而不是connect
        bridge.call(
            handlerName: "bridgeCommonCall",
            data: [
                "name": "searchDevices",
                "data": [
                    "uuid": deviceId
                ],
            ]
        ) { responseData in
            print("Device connection result:", responseData ?? "nil")
        }
    }

    func registerBridgeHandler() {
        print("=== Starting to register bridge handlers ===")

        registerBasicHandlers()
        registerUIHandlers()
    }

    // 修改更新结果显示的方法 - 直接赋值而不是累加
    func updateResultText(_ text: String) {
        DispatchQueue.main.async {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            let timestamp = dateFormatter.string(from: Date())

            // 直接赋值不追加
            self.resultTextView.text = "[\(timestamp)] \(text)"
        }
    }
}

// MARK: - Bridge Handlers
extension ViewController {
    func registerBasicHandlers() {
        // enumerate
        bridge.register(handlerName: "enumerate") { parameters, callback in
            print("🔵 enumerate called with parameters:", parameters ?? "nil")

            // 检查是否已有连接的设备，如果有且参数中指定了设备ID，则无需重新扫描
            if let peripheral = self.peripheral,
                let params = parameters as? [String: Any],
                let data = params["data"] as? [String: Any],
                let connectId = data["connectId"] as? String,
                !connectId.isEmpty,
                peripheral.identifier.uuidString == connectId
            {

                print("🔵 Already connected to device, no need to scan")
                callback?([
                    [
                        "name": peripheral.name ?? "Unnamed Device",
                        "id": peripheral.identifier.uuidString,
                    ]
                ])
                return
            }

            // 如果已经在累积设备过程中
            if self.isAccumulatingDevices {
                if let callback = callback {
                    // 保存回调，在扫描完成后一次性调用
                    self.enumerateCallback = callback
                    print("🔵 Storing enumerate callback for later use")
                }
                return
            }

            // 如果搜索中但不是累积设备过程，则启动搜索
            if self.isSearching {
                // 保存回调
                if let callback = callback {
                    self.searchDeviceCallback = callback
                    print("🔵 Storing search device callback")
                } else {
                    print("⚠️ No callback provided for enumerate")
                }

                // 启动扫描
                self.manager.scanForPeripherals(
                    withServices: [CBUUID(string: self.serviceID)], options: nil)
                print("🔵 Started scanning for peripherals with ServiceID:", self.serviceID)

                // 设置超时自动清除callback
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if self.searchDeviceCallback != nil {
                        print("🔵 Clearing search device callback after timeout")
                        self.searchDeviceCallback = nil
                        self.manager.stopScan()
                    }
                }
            } else if let peripheral = self.peripheral {
                // 如果不是搜索场景，但有已保存的设备，直接返回
                if peripheral.identifier.uuidString.count > 0 {
                    print("🔵 Returning existing peripheral:", peripheral.name ?? "unnamed")
                    callback?([
                        [
                            "name": peripheral.name ?? "Unnamed Device",
                            "id": peripheral.identifier.uuidString,
                        ]
                    ])
                }
            }
        }

        // connect
        bridge.register(handlerName: "connect") { params, callback in
            if let uuid = params?["uuid"] as? String, !uuid.isEmpty {
                print("🔵 Connecting to device with UUID:", uuid)

                // If we have a peripheral but with different ID, we need to find the new one
                if self.peripheral == nil || self.peripheral.identifier.uuidString != uuid {
                    print("⚠️ No matching peripheral found in memory, starting scan to find device")
                    self.manager.scanForPeripherals(
                        withServices: [CBUUID(string: self.serviceID)], options: nil)
                } else {
                    self.manager.connect(self.peripheral)
                    print("🔵 Connecting to existing peripheral:", self.peripheral.name ?? "unnamed")
                }

                callback?(["success": true])
            } else {
                print("⚠️ Invalid UUID for connect")
                callback?(["success": false, "error": "Invalid UUID"])
            }
        }

        // disconnect
        bridge.register(handlerName: "disconnect") { _, callback in
            self.manager.cancelPeripheralConnection(self.peripheral)
            callback?(["success": true])
        }

        // send
        bridge.register(handlerName: "send") { params, callback in
            print("called send method: ", params ?? "")
            if let data = params?["data"] as? String {
                print("🔵 Sending data:", data)
                self.peripheral.writeValue(
                    data.hexData, for: self.writeCharacteristic, type: .withoutResponse)
                callback?(["success": true])
            }
        }
    }

    func registerUIHandlers() {
        // requestPinInput handler
        bridge.register(handlerName: "requestPinInput") { _, callback in
            print("🔵 PIN input requested")

            DispatchQueue.main.async {
                self.showPinInputDialog(callback: callback)
            }
        }

        // requestButtonConfirmation handler
        bridge.register(handlerName: "requestButtonConfirmation") { params, callback in
            print("🔵 Button confirmation requested")

            var message = "Please confirm on your device"
            if let paramDict = params as? [String: Any],
                let msgText = paramDict["message"] as? String
            {
                message = msgText
            }

            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Confirm Operation", message: message, preferredStyle: .alert)

                alert.addAction(
                    UIAlertAction(title: "OK", style: .default) { _ in
                        callback?(nil)
                    })

                self.present(alert, animated: true)
            }
        }

        // closeUIWindow handler
        bridge.register(handlerName: "closeUIWindow") { _, callback in
            print("🔵 Close UI window requested")
            callback?(nil)
        }
    }

    // 显示PIN码输入对话框，类似于Android的实现
    func showPinInputDialog(callback: ((Any?) -> Void)?) {
        // 定义键盘映射，与Android端相同
        let keyboardMap = ["7", "8", "9", "4", "5", "6", "1", "2", "3"]

        // 创建半透明背景
        let overlayView = UIView(frame: self.view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.tag = 2001  // 用于后续识别和移除

        // 创建对话框容器 - 增加高度确保所有元素可见
        let dialogWidth: CGFloat = min(self.view.bounds.width - 40, 300)
        let dialogHeight: CGFloat = 480  // 进一步增加高度

        let dialogView = UIView(
            frame: CGRect(
                x: (self.view.bounds.width - dialogWidth) / 2,
                y: (self.view.bounds.height - dialogHeight) / 2,
                width: dialogWidth,
                height: dialogHeight
            ))
        dialogView.backgroundColor = UIColor.white
        dialogView.layer.cornerRadius = 10

        // 标题
        let titleLabel = UILabel(frame: CGRect(x: 10, y: 15, width: dialogWidth - 20, height: 30))
        titleLabel.text = "PIN Input"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        dialogView.addSubview(titleLabel)

        // PIN显示区域
        let pinDisplayView = UILabel(
            frame: CGRect(x: 20, y: 55, width: dialogWidth - 40, height: 40))
        pinDisplayView.layer.borderWidth = 1
        pinDisplayView.layer.borderColor = UIColor.lightGray.cgColor
        pinDisplayView.layer.cornerRadius = 5
        pinDisplayView.textAlignment = .center
        pinDisplayView.font = UIFont.systemFont(ofSize: 20)
        pinDisplayView.tag = 2002  // 用于后续更新内容
        dialogView.addSubview(pinDisplayView)

        // 存储PIN码
        var pinSequence = ""

        // 创建数字按钮 - 进一步减小按钮尺寸
        let buttonSize: CGFloat = (dialogWidth - 100) / 3  // 更小的按钮尺寸
        let startY: CGFloat = 110
        let buttonSpacing: CGFloat = 12  // 增加按钮间距

        for index in 0..<9 {
            let row = index / 3
            let col = index % 3

            let buttonX = 25 + CGFloat(col) * (buttonSize + buttonSpacing)
            let buttonY = startY + CGFloat(row) * (buttonSize + buttonSpacing)

            let button = UIButton(
                frame: CGRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize))
            // 不设置按钮标题，保持纯蓝色圆形
            button.backgroundColor = UIColor.systemBlue
            button.layer.cornerRadius = buttonSize / 2
            button.tag = index  // 仍使用索引作为tag，但不显示数字

            button.addTarget(self, action: #selector(pinButtonPressed(_:)), for: .touchUpInside)

            dialogView.addSubview(button)
        }

        // 确认按钮 - 确保位于数字键盘下方且在对话框内，给足够空间
        let confirmButtonY = startY + 3 * (buttonSize + buttonSpacing) + 30  // 增加间距
        let confirmButton = UIButton(
            frame: CGRect(
                x: 20,
                y: confirmButtonY,
                width: dialogWidth - 40,
                height: 45  // 稍微增大确认按钮高度
            ))
        confirmButton.setTitle("Confirm", for: .normal)
        confirmButton.setTitleColor(UIColor.white, for: .normal)
        confirmButton.backgroundColor = UIColor.systemGreen
        confirmButton.layer.cornerRadius = 5
        confirmButton.addTarget(self, action: #selector(confirmPinPressed(_:)), for: .touchUpInside)
        dialogView.addSubview(confirmButton)

        // 使用设备PIN按钮 - 确保位于确认按钮下方且在对话框内
        let useDeviceButtonY = confirmButtonY + 55  // 增加与确认按钮的间距
        let useDeviceButton = UIButton(
            frame: CGRect(
                x: 20,
                y: useDeviceButtonY,
                width: dialogWidth - 40,
                height: 30
            ))
        useDeviceButton.setTitle("Use Device PIN", for: .normal)
        useDeviceButton.setTitleColor(UIColor.systemBlue, for: .normal)
        useDeviceButton.backgroundColor = UIColor.clear
        useDeviceButton.addTarget(
            self, action: #selector(useDevicePinPressed(_:)), for: .touchUpInside)
        dialogView.addSubview(useDeviceButton)

        // 将数据存储在对话框视图中
        let pinData = PinInputData(callback: callback, pinSequence: pinSequence)
        objc_setAssociatedObject(
            dialogView, &AssociatedKeys.pinInputData, pinData, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // 显示对话框
        overlayView.addSubview(dialogView)
        self.view.addSubview(overlayView)

        // 添加点击背景关闭的手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissPinDialog))
        tapGesture.delegate = self
        overlayView.addGestureRecognizer(tapGesture)
    }

    @objc func pinButtonPressed(_ sender: UIButton) {
        // 获取当前对话框
        guard let overlayView = self.view.viewWithTag(2001),
            let dialogView = overlayView.subviews.first,
            let pinDisplayView = dialogView.viewWithTag(2002) as? UILabel,
            let pinData = objc_getAssociatedObject(dialogView, &AssociatedKeys.pinInputData)
                as? PinInputData
        else {
            return
        }

        // 获取按钮对应的数字
        let keyboardMap = ["7", "8", "9", "4", "5", "6", "1", "2", "3"]
        let digit = keyboardMap[sender.tag]

        // 更新PIN码
        var pinSequence = pinData.pinSequence
        pinSequence.append(digit)

        // 创建新的PinInputData并保存
        let newPinData = PinInputData(callback: pinData.callback, pinSequence: pinSequence)
        objc_setAssociatedObject(
            dialogView, &AssociatedKeys.pinInputData, newPinData, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        // 更新显示 - 只显示点号而不是数字
        pinDisplayView.text = String(repeating: "•", count: pinSequence.count)

        // 添加按钮按下效果
        UIView.animate(
            withDuration: 0.1,
            animations: {
                sender.alpha = 0.5
            }
        ) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.alpha = 1.0
            }
        }
    }

    @objc func confirmPinPressed(_ sender: UIButton) {
        // 获取当前对话框
        guard let overlayView = self.view.viewWithTag(2001),
            let dialogView = overlayView.subviews.first,
            let pinData = objc_getAssociatedObject(dialogView, &AssociatedKeys.pinInputData)
                as? PinInputData
        else {
            return
        }

        let pinSequence = pinData.pinSequence

        if !pinSequence.isEmpty {
            // 调用回调并传递PIN码
            pinData.callback?(pinSequence)

            // 添加到结果显示
            self.updateResultText(
                "PIN entered: \(String(repeating: "*", count: pinSequence.count))")

            // 关闭对话框
            overlayView.removeFromSuperview()
        } else {
            // PIN码为空时显示警告
            let warningLabel = UILabel(
                frame: CGRect(x: 20, y: 95, width: dialogView.bounds.width - 40, height: 15))
            warningLabel.text = "Please enter PIN"
            warningLabel.textColor = UIColor.red
            warningLabel.textAlignment = .center
            warningLabel.font = UIFont.systemFont(ofSize: 12)

            // 移除旧的警告标签（如果有）
            dialogView.subviews.filter { $0.tag == 2003 }.forEach { $0.removeFromSuperview() }

            warningLabel.tag = 2003
            dialogView.addSubview(warningLabel)

            // 震动效果
            dialogView.shakeView()
        }
    }

    @objc func useDevicePinPressed(_ sender: UIButton) {
        // 获取当前对话框
        guard let overlayView = self.view.viewWithTag(2001),
            let dialogView = overlayView.subviews.first,
            let pinData = objc_getAssociatedObject(dialogView, &AssociatedKeys.pinInputData)
                as? PinInputData
        else {
            return
        }

        // 调用回调，传递空字符串表示使用设备PIN
        pinData.callback?("")

        // 添加到结果显示
        self.updateResultText("Using device PIN")

        // 关闭对话框
        overlayView.removeFromSuperview()
    }

    @objc func dismissPinDialog() {
        if let overlayView = self.view.viewWithTag(2001) {
            overlayView.removeFromSuperview()
        }
    }
}

// 用于存储与视图关联的数据
private struct AssociatedKeys {
    static var pinInputData = "pinInputData"
}

// 存储PIN输入数据
class PinInputData {
    let callback: ((Any?) -> Void)?
    let pinSequence: String

    init(callback: ((Any?) -> Void)?, pinSequence: String) {
        self.callback = callback
        self.pinSequence = pinSequence
    }
}

// 添加视图震动效果
extension UIView {
    func shakeView() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        animation.duration = 0.6
        animation.values = [-10.0, 10.0, -7.0, 7.0, -5.0, 5.0, 0.0]
        layer.add(animation, forKey: "shake")
    }
}

//MARK:- CBCentralManagerDelegate
extension ViewController: CBCentralManagerDelegate {
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("🔵 Bluetooth state updated:", central.state.rawValue)
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on and ready")

            // If we have a cached device, try to reconnect
            if let deviceId = self.device?.getConnectId(), !deviceId.isEmpty {
                // Convert string UUID to UUID object
                if let uuid = UUID(uuidString: deviceId) {
                    let peripherals = self.manager.retrievePeripherals(withIdentifiers: [uuid])
                    if let peripheral = peripherals.first {
                        self.peripheral = peripheral
                        print("✅ Retrieved cached peripheral:", peripheral.name ?? "unnamed")
                    } else {
                        print("⚠️ Could not retrieve cached peripheral")
                    }
                }
            }

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

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        print(
            "🔵 Discovered peripheral:", peripheral.name ?? "unnamed", "id:",
            peripheral.identifier.uuidString)

        // 存储发现的设备信息
        let deviceInfo: [String: String] = [
            "name": peripheral.name ?? "Unnamed Device",
            "id": peripheral.identifier.uuidString,
        ]

        self.peripheral = peripheral
        print("✅ Stored peripheral reference")

        // 如果正在累积设备，添加到列表
        if isAccumulatingDevices {
            // 检查设备是否已在列表中
            if !accumulatedDevices.contains(where: { $0["id"] == deviceInfo["id"] }) {
                accumulatedDevices.append(deviceInfo)
                print("✅ Added device to accumulated list: \(deviceInfo["name"] ?? "unnamed")")
            }
        }

        // 如果我们有一个缓存的设备ID，并且这个外设匹配，则连接到它
        if let deviceId = self.device?.getConnectId(), deviceId == peripheral.identifier.uuidString
        {
            print("🔵 Found cached peripheral, connecting...")
            central.stopScan()
            central.connect(peripheral, options: nil)
        }

        // 调用搜索设备回调（如果有）
        if let callback = searchDeviceCallback {
            print("🔵 Calling search device callback")
            callback([deviceInfo])
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to peripheral: \(peripheral.name ?? "unnamed")")

        // 清除搜索回调，防止继续接收搜索结果
        self.searchDeviceCallback = nil

        //discover all service
        peripheral.discoverServices(nil)
        peripheral.delegate = self
    }
}

//MARK:- CBPeripheralDelegate
extension ViewController: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        if let services = peripheral.services {

            //discover characteristics of services
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {

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
            if setWriteC && setNotifyC {
                print("Set Characteristic Success")
                bridge.call(handlerName: "connectFinished", data: nil)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
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

// MARK: - UITableViewDataSource & UITableViewDelegate
extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scannedDevices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath)

        if indexPath.row < scannedDevices.count {
            let device = scannedDevices[indexPath.row]
            let name = device["name"] ?? "Unnamed Device"
            cell.textLabel?.text = name
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectDeviceFromTable(at: indexPath)
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

// MARK: - UIGestureRecognizerDelegate
extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
    {
        // Only respond to taps on the overlay background, not on its subviews
        if touch.view?.tag == 1001 {
            return true
        }
        return false
    }
}

// MARK: - Button Actions
extension ViewController {
    @objc func onGetFeatures() {
        print("🔵 onGetFeatures called")
        let data: [String: Any] = [
            "name": "getFeatures",
            "data": [
                "connectId": self.device?.getConnectId() ?? "",
                "deviceId": self.device?.getDeviceId() ?? "",
            ],
        ]

        bridge.call(handlerName: "bridgeCommonCall", data: data) { responseData in
            print("getFeatures response: ", responseData ?? "")
            if let responseDictionary = responseData as? [String: Any] {
                self.updateResultText("Features: \(responseDictionary)")

                if let success = responseDictionary["success"] as? Int,
                    success == 1,
                    let payload = responseDictionary["payload"] as? [String: Any],
                    let deviceId = payload["device_id"] as? String
                {
                    self.device = Device(
                        connectId: self.device?.getConnectId()
                            ?? self.peripheral.identifier.uuidString, deviceId: deviceId)
                    print(
                        "✅ Device updated - connectId:", self.device?.getConnectId() ?? "",
                        "deviceId:", self.device?.getDeviceId() ?? "")
                } else {
                    print("⚠️ Invalid response format or unsuccessful response")
                }
            } else {
                print("⚠️ Could not parse response as dictionary")
                self.updateResultText("Failed to get features")
            }
        }
    }

    @objc func onGetBitcoinAddress() {
        bridge.call(
            handlerName: "bridgeCommonCall",
            data: [
                "name": "btcGetAddress",
                "data": [
                    "connectId": self.device?.getConnectId() ?? "",
                    "deviceId": self.device?.getDeviceId() ?? "",
                    "path": "m/49'/0'/0'/0/0",
                    "coin": "btc",
                    "showOnOneKey": true,
                    "useEmptyPassphrase": true,
                ],
            ] as [String: Any]
        ) { response in
            print("get bitcoin address response: ", response ?? "")
            if let responseDict = response as? [String: Any] {
                self.updateResultText("Bitcoin Address: \(responseDict)")
            } else {
                self.updateResultText("Failed to get Bitcoin address")
            }
        }
    }

    @objc func onGetEvmAddress() {
        print("🔵 onGetEvmAddress called")

        bridge.call(
            handlerName: "bridgeCommonCall",
            data: [
                "name": "evmGetAddress",
                "data": [
                    "connectId": self.device?.getConnectId() ?? "",
                    "deviceId": self.device?.getDeviceId() ?? "",
                    "path": "m/44'/60'/0'/0/0",
                    "chainId": 1,
                    "showOnOneKey": true,
                    "useEmptyPassphrase": true,
                ],
            ] as [String: Any]
        ) { response in
            print("get EVM address response: ", response ?? "")
            if let responseDict = response as? [String: Any] {
                self.updateResultText("EVM Address: \(responseDict)")
            } else {
                self.updateResultText("Failed to get EVM address")
            }
        }
    }

    @objc func onCheckFirmwareRelease() {
        print("🔵 onCheckFirmwareRelease called")

        bridge.call(
            handlerName: "bridgeCommonCall",
            data: [
                "name": "checkFirmwareRelease",
                "data": [
                    "connectId": self.device?.getConnectId() ?? "",
                    "deviceId": self.device?.getDeviceId() ?? "",
                ],
            ] as [String: Any]
        ) { response in
            print("Check Firmware Release response: ", response ?? "")

            // 更新结果显示
            if let responseDict = response as? [String: Any] {
                self.updateResultText("Firmware Release: \(responseDict)")
            } else {
                self.updateResultText("Failed to check firmware")
            }

            // 显示结果弹窗
            DispatchQueue.main.async {
                var message = "Failed to check firmware"
                if let responseDict = response as? [String: Any] {
                    // Fix: using description directly as it's not optional
                    message = responseDict.description
                }

                let alert = UIAlertController(
                    title: "Firmware Check Result", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    @objc func onCheckBleFirmwareRelease() {
        print("🔵 onCheckBleFirmwareRelease called")

        bridge.call(
            handlerName: "bridgeCommonCall",
            data: [
                "name": "checkBLEFirmwareRelease",
                "data": [
                    "connectId": self.device?.getConnectId() ?? "",
                    "deviceId": self.device?.getDeviceId() ?? "",
                ],
            ] as [String: Any]
        ) { response in
            print("Check BLE Firmware Release response: ", response ?? "")

            // 更新结果显示
            if let responseDict = response as? [String: Any] {
                self.updateResultText("BLE Firmware Release: \(responseDict)")
            } else {
                self.updateResultText("Failed to check BLE firmware")
            }

            // 显示结果弹窗
            DispatchQueue.main.async {
                var message = "Failed to check BLE firmware"
                if let responseDict = response as? [String: Any] {
                    // Fix: using description directly as it's not optional
                    message = responseDict.description
                }

                let alert = UIAlertController(
                    title: "BLE Firmware Check Result", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}
