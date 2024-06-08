import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralManagerDelegate, BLEClientViewControllerDelegate {
    
    var peripheralManager: CBPeripheralManager?
    var characteristic: CBMutableCharacteristic?
    //let serviceUUID = CBUUID(string: "180D")
    let characteristicUUID = CBUUID(string: "2A37")
    var synAckReceived = false
    
    @IBOutlet var toggleClient: UISegmentedControl!
    @IBOutlet var onOff: UILabel!
    @IBOutlet var message: UITextField!
    @IBOutlet var manualPort: UITextField!
    var toggleButton: UIButton!
    var finAck = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toggleClient.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        let logoTransparent = UIImage(named: "onButton")?.scaleImage(toHeight: 200)
        toggleButton = UIButton()
        toggleButton.setImage(logoTransparent, for: .normal)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.layer.cornerRadius = 100
        toggleButton.clipsToBounds = true
        view.addSubview(toggleButton)
        NSLayoutConstraint.activate([
            toggleButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            toggleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        toggleButton.addTarget(self, action: #selector(toggleAdvertising(_:)), for: .touchUpInside)
        
        let keyboardGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(keyboardGesture)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Reset the segmented control to the first segment (index 0)
        print("viewWillAppear: Resetting segmented control to index 0")
        toggleClient.selectedSegmentIndex = 0
        segmentChanged(toggleClient)
    }
    
    func didReceiveData(_ data: String) {
        print("Received data from BLEClientViewController: \(data)")
        if (data == "Dismissed BLEClientViewController") {
            toggleClient.selectedSegmentIndex = 0
            synAckReceived = false
            sleep(2)
            onOff.text = "Server Disconnected"
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("Bluetooth is powered on")
        } else {
            print("Bluetooth is not available")
        }
    }
    
    func startAdvertising() {
        characteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        if (manualPort.text == "") { manualPort.text = "180D"}
        let service = CBMutableService(type: CBUUID(string: manualPort.text!), primary: true)
        service.characteristics = [characteristic!]
        
        peripheralManager?.add(service)
        peripheralManager?.startAdvertising([
            CBAdvertisementDataLocalNameKey: "SYN Message",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: manualPort.text!)]
        ])
        onOff.text = "Sent SYN..."
    }
    
    /*
     Turn off the ble broadcasting
     */
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        print("Stopped advertising")
    }
    
    /*
     Handles potential errors when firing up the service
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("Error adding service: \(error.localizedDescription)")
        } else {
            print("Service added successfully")
        }
    }
    
    /*
     After server sends the syn+ack (acknowledgment that they read the initial syn, we will send them the data
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if (finAck) {
            request.value = "Final ACK".data(using: .utf8)
            peripheralManager?.respond(to: request, withResult: .success)
            sleep(4)
            toggleAdvertising(toggleButton)
        }
        else if (synAckReceived) {
            if request.characteristic.uuid == characteristicUUID {
                if (message.text == "") { message.text = "hello world"}
                request.value = message.text?.data(using: .utf8)
                peripheralManager?.respond(to: request, withResult: .success)
            }
        }
        else {
            if request.characteristic.uuid == characteristicUUID {
                request.value = "ACK".data(using: .utf8)
                peripheralManager?.respond(to: request, withResult: .success)
                sleep(2)
                synAckReceived = true
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == characteristicUUID {
                characteristic?.value = request.value
                peripheralManager?.respond(to: request, withResult: .success)
                if let data = request.value, let receivedString = String(data: data, encoding: .utf8) {
                    print("Received: \(receivedString)")
                    if (receivedString == "SYN+ACK") {
                        onOff.text = "Received a SYN+ACK. Sending ACK..."
                    }
                    else {
                        finAck = true
                        sleep(2)
                        onOff.text = "Server received message"
                    }
                }
            }
        }
    }
    
    @objc func segmentChanged(_ sender: UISegmentedControl) {
        print("segmentChanged: Segment index is now \(sender.selectedSegmentIndex)")
        switch sender.selectedSegmentIndex {
        case 1:
            print("segmentChanged: Performing segue to client")
            if (manualPort.text == "") {manualPort.text = "180D"}
            self.performSegue(withIdentifier: "toClient", sender: manualPort.text)
        case 0:
            print("segmentChanged: On Server")
        default:
            break
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toClient" {
            if let bleProfile = segue.destination as? BLEClientViewController, let portID = sender as? String {
                print("HI")
                bleProfile.serviceUUID = CBUUID(string: portID)
                bleProfile.tempPort = portID
            }
        }
    }
    
    @objc func toggleAdvertising(_ sender: UIButton) {
        if sender.isSelected {
            onOff.text = "Sending Off:"
            stopAdvertising()
        } else {
            onOff.text = "Sending..."
            startAdvertising()
        }
        sender.isSelected.toggle()
    }
}

extension UIImage {
    func scaleImage(toHeight newHeight: CGFloat) -> UIImage? {
        let scale = newHeight / self.size.height
        let newWidth = self.size.width * scale
        UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, 0.0)
        self.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
    
    func squareImage(toSideLength sideLength: CGFloat) -> UIImage? {
        let newSize = CGSize(width: sideLength, height: sideLength)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        
        let widthRatio = sideLength / size.width
        let heightRatio = sideLength / size.height
        let scaleRatio = max(widthRatio, heightRatio)
        
        let scaledImageSize = CGSize(width: size.width * scaleRatio, height: size.height * scaleRatio)
        let center = CGPoint(x: newSize.width/2, y: newSize.height/2)
        let drawRect = CGRect(x: center.x - scaledImageSize.width/2, y: center.y - scaledImageSize.height/2, width: scaledImageSize.width, height: scaledImageSize.height)
        
        self.draw(in: drawRect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
