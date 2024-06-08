import UIKit
import CoreBluetooth

protocol BLEClientViewControllerDelegate: AnyObject {
    func didReceiveData(_ data: String)
}

class BLEClientViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    weak var delegate: BLEClientViewControllerDelegate?
    var centralManager: CBCentralManager?
    var discoveredPeripheral: CBPeripheral?
    
    var serviceUUID = CBUUID(string: "180D")
    let characteristicUUID = CBUUID(string: "2A37")
    @IBOutlet var tempMessage: UILabel!
    @IBOutlet var status: UILabel!
    var tempPort = "0000"
    @IBOutlet var portNumber: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        portNumber.text = tempPort
        // Initialize central manager
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Add a button to dismiss the view controller
        let dismissButton = UIButton(type: .system)
        dismissButton.setTitle("Dismiss", for: .normal)
        dismissButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dismissButton)
        NSLayoutConstraint.activate([
            dismissButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
    
    @objc func dismissSelf() {
        if let peripheral = discoveredPeripheral {
            // Unsubscribe from notifications and disconnect the peripheral
            if let characteristic = peripheral.services?.first(where: { $0.uuid == serviceUUID })?.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
                peripheral.setNotifyValue(false, for: characteristic)
            }
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        dismiss(animated: true) {
            // Inform the delegate that the view controller was dismissed
            self.delegate?.didReceiveData("Dismissed BLEClientViewController")
        }
    }
    
    // MARK: - Central Manager Delegate Methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func startScanning() {
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
            centralManager?.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        centralManager?.stopScan()
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == serviceUUID {
                    status.text = "SYN Discovered preparing to send SYN+ACK"
                    print("discovered a syn, checking if characteristics id matches...")
                    peripheral.discoverCharacteristics([characteristicUUID], for: service)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == characteristicUUID {
                    sleep(2)
                    sendData(to: peripheral, data: "SYN+ACK")
                    status.text = "SYN+ACK Sent..."
                    // Notifies the client that the initial syn has been read, equivalent of syn+ack
                    sleep(2)
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                    sleep(2)
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == characteristicUUID {
            if let data = characteristic.value, let receivedString = String(data: data, encoding: .utf8) {
                print("Received: \(receivedString)")
                if (receivedString == "ACK") {
                    status.text = "ACK received, ready to receive data"
                } else {
                    tempMessage.text = receivedString
                    sendData(to: peripheral, data: "Received Message")
                }
            }
        }
    }
    
    func sendData(to peripheral: CBPeripheral, data: String) {
        if let dataToSend = data.data(using: .utf8), let characteristic = peripheral.services?.first(where: { $0.uuid == serviceUUID })?.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
            peripheral.writeValue(dataToSend, for: characteristic, type: .withResponse)
        }
    }
}
