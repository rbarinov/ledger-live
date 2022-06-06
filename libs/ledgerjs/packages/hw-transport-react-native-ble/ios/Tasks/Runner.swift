//
//  Runner.swift
//  hw-transport-react-native-ble
//
//  Created by Juan on 28/5/22.
//

import Foundation
import Starscream
import BleTransport

class Runner: NSObject  {
    var endpoint : URL
    
    var onEmit: ((Action, ExtraData?)->Void)?
    var onDone: ((String, String)->Void)?
    var onStop: (()->Void)?
    var initialMessage: String = ""
    
    var isRunning: Bool = false
    var isUserBlocked: Bool = false
    var isInBulkMode: Bool = false
    var pendingOnDone: Bool = false
    var socket: WebSocket?
    
    var HSMNonce: Int = 0               /// HSM uses this nonce to know which frame we are replying to
    var APDUMaxCount: Int = 0
    var APDUQueue: [APDU] = []
    var lastBLEResponse: String = ""
    var lastScriptRunnerMessage: String = ""

    var stopped: Bool = false

    public func setURL(_ url : URL) {
        self.endpoint = url
    }

    convenience init (
        endpoint : URL,
        onEvent: @escaping ((Action, ExtraData?)->Void),
        onDone: ((String, String)->Void)?,
        withInitialMessage: String
    ) {
        self.init(endpoint: endpoint, onEvent: onEvent, onDone: onDone)
        self.initialMessage = withInitialMessage
    }
    
    public init (
        endpoint : URL,
        onEvent: @escaping ((Action, ExtraData?)->Void),
        onDone: ((String, String)->Void)?
    ) {
        self.endpoint = endpoint
        self.isRunning = true
        self.onEmit = onEvent
        self.onDone = onDone
        
        super.init()
        self.startScriptRunner()
    }
    
    
    public func stop(_ onStop: @escaping (()->Void)) {
        self.stopped = true
        socket?.disconnect()

        if self.APDUQueue.count > 0 && self.isInBulkMode {
            self.onStop = onStop
            self.APDUQueue = [
                APDU(raw: "e00000001eed04c62fde5006534e14e7f339b2a55262bb118e41f552912179ac3445d0"),
            ]
        } else {
            onStop()
        }
    }
    
    /// Based on the apdu in/out we can infer some events that we need to emit up to javascript. Not all exchanges need an event.
    private func maybeEmitEvent(_ apdu : String, fromHSM: Bool = true) {
        if fromHSM && apdu.starts(with: "e051") {
            self.isUserBlocked = true
            self.onEmit!(Action.permissionRequested, nil)
        } else if !fromHSM && self.isUserBlocked {
            self.isUserBlocked = false
            if apdu.suffix(4) == "9000" {
                self.onEmit!(Action.permissionGranted, nil)
            } else {
                self.onEmit!(Action.permissionRefused, nil)
            }
        } else if self.isInBulkMode {
            let progress = ((Double(self.APDUMaxCount-self.APDUQueue.count))/Double(self.APDUMaxCount))
            self.onEmit!(Action.bulkProgress, ExtraData(progress: progress))
        }
        
    }
    
    private func startScriptRunner() -> Void {
        var request = URLRequest(url: self.endpoint)
        request.timeoutInterval = 20 // No idea if we need this much
        socket = WebSocket(request: request)
        socket!.connect()
        socket!.onEvent = { event in
            switch event {
            case .connected(_):
                // In the case of BIM, we should initiate the message exchange
                if self.initialMessage != "" {
                    self.socket!.write(string: self.initialMessage)
                }
                break
            case .disconnected(let reason, _):
                /// We need to communicate this **only** when have finished the device exchange.
                /// Never forget that we are a bridge between a backend and the device and even though
                /// the communication with the backend may over, we may very well still be communicating
                /// with the device.
                if !self.isInBulkMode {
                    self.onDone!(reason, self.lastScriptRunnerMessage)
                } else {
                    self.pendingOnDone = true
                }
                break
            case .text(let msg):
                self.lastScriptRunnerMessage = msg
                // Receive a message from the scriptrunner
                let data = Data(msg.utf8)
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        let query = json["query"] as? String;
                        if (query == "bulk") {
                            let rawAPDUs = json["data"] as? [String] ?? []
                            self.APDUQueue = []
                            self.isInBulkMode = true
                            self.APDUMaxCount = rawAPDUs.count // Used for percentage reports
                            
                            for rawAPDU in rawAPDUs {
                                self.APDUQueue.append(APDU(raw: rawAPDU));
                            }
                        } else {
                            self.isInBulkMode = false
                            self.APDUQueue = [APDU(raw: json["data"] as? String ?? "")]
                            self.HSMNonce = json["nonce"] as? Int ?? 0;
                        }
                        self.handleNextAPDU();
                    }
                } catch {
                    print("Failed to load: \(error.localizedDescription)")
                }
                break
            default:
                break
            }
        }
    }
    
    func handleNextAPDU() -> Void {
        if let onStop = self.onStop {
            /// We have been stopped mid bulk exchange, send a cleanup apdu to get out of it.
            /// This apdu is an 'openApp' command with a white space as the app name, this causes a 6870
            /// response, we follow that with a getAppAndVersion apdu which also fails. Then we can disconnect.
            if self.APDUQueue.count > 0 {
                let apdu = self.APDUQueue.removeFirst()
                self.maybeEmitEvent((apdu.data.hexEncodedString()))
                BleTransport.shared.exchange(apdu: apdu) { _ in
                    self.handleNextAPDU()
                }
            } else {
                onStop()
            }
        } else if !self.APDUQueue.isEmpty {
            let apdu = self.APDUQueue.removeFirst()
            self.maybeEmitEvent((apdu.data.hexEncodedString()))
            BleTransport.shared.exchange(apdu: apdu, callback: self.onDeviceResponse)
        } else if self.pendingOnDone {
            /// We don't have pending apdus, and we have gone past a bulk payload, we can emit the disconnect
            self.onDone!("reason", self.lastScriptRunnerMessage) // TODO not quite right
        }
    }
    
    func onDeviceResponse(_ result : Result<String, BleTransportError>) {
        switch result {
        case .success(let response):
            let status = response.suffix(4)
            let data = response.dropLast(4)
            
            self.maybeEmitEvent(response, fromHSM: false)
            if (status == "9000") {
                if (self.isInBulkMode) {
                    self.handleNextAPDU()
                } else {
                    // Send message back to the script runner
                    // Probably a good idea to move this to an encoded string
                    let response = "{\"nonce\":\(self.HSMNonce),\"response\":\"success\",\"data\":\"\(data)\"}"
                    self.socket!.write(string: response)
                }
            }
        case .failure(let error):
            print(error)
        }
    }
}

struct HSMResponse: Codable {
    let nonce: Int
    let response: String
    let data: String
}
