//
//  ViewController.swift
//  RemoteBolus
//
//  Created by Vladimir Tchernitski on 02/04/2019.
//  Copyright © 2019 Vladimir Tchernitski. All rights reserved.
//

import UIKit
import OpenSSL


enum Status {
    case newBolus
    case newBolusAmount
    case setBolus
    case updateBolus
    case deleteBolus
}

enum T1DError: Error {
    case invalidAmount
}

public struct RuntimeError: Error {
    private let message: String
    
    public init(_ message: String) {
        self.message = message
    }
    
    var localizedDescription: String {
        return message
    }
}

extension Push {
    public static func setup() {
        SSL_library_init()
        SSL_load_error_strings()
        OPENSSL_add_all_algorithms_noconf()
    }
    
    public static func cleanup() {
        ERR_free_strings()
        EVP_cleanup()
        CRYPTO_cleanup_all_ex_data()
    }
}


public struct Key {
    private let pKey: EVP_PKEY?
    
    public static func loadPKCS8(_ path: String) throws -> Key {
        let bio = BIO_new_file(path, "rb")
        var privateKey: UnsafeMutablePointer<EVP_PKEY>? = nil
        PEM_read_bio_PrivateKey(bio, &privateKey, nil, nil)
        BIO_free(bio)
        return Key(pKey: privateKey?.pointee)
    }
    
    public func canSign() -> Bool {
        return self.pKey != nil
    }
    
    public func sign(_ data: Data) throws -> Data {
        guard var pKey = self.pKey else {
            throw RuntimeError("Invalid EC Private Key")
        }

        let ctx = EVP_MD_CTX_create()
        let md = EVP_get_digestbyname(SN_ecdsa_with_SHA256) ?? EVP_get_digestbyname(SN_sha256)
        EVP_DigestInit_ex(ctx, md, nil)
        EVP_DigestSignInit(ctx, nil, md, nil, &pKey)
        _ = data.withUnsafeBytes({
            EVP_DigestUpdate(ctx, $0.baseAddress, data.count)
        })

        var sigLen = 0
        EVP_DigestSignFinal(ctx, nil, &sigLen)

        var signature = [UInt8](repeating: 0x00, count: sigLen)
        EVP_DigestSignFinal(ctx, &signature, &sigLen)
        EVP_MD_CTX_destroy(ctx)
        return Data(bytes: signature, count: sigLen)
    }
}


public struct Push {
    private let key: Key
    private let bundleId: String
    private let keyId: String
    private let teamId: String
    private let isProduction: Bool
    private let authenticator: PushAuthenticator
    
    public init(bundleId: String, keyId: String, teamId: String, key: Key, isProduction: Bool) {
        self.bundleId = bundleId
        self.keyId = keyId
        self.teamId = teamId
        self.isProduction = isProduction
        self.key = key
        self.authenticator = PushAuthenticator(key: key)
    }
    
    public func push(deviceId: String, payload: [String: Any], expiration: Int64, _ completion: ((Error?) -> Void)?) {
        do {
            var request = URLRequest(url: URL(string: self.baseURL(deviceId))!)
            request.httpMethod = "POST"
            
            request.allHTTPHeaderFields = [
                "apns-id": UUID().uuidString,
                "apns-topic": bundleId,
                "apns-priority": "5",
                "apns-expiration": "\(expiration)"
            ]
            
            if self.key.canSign() {
                request.addValue("bearer \(try self.generateJwtToken())", forHTTPHeaderField: "authorization")
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            
            URLSession(configuration: .ephemeral, delegate: self.authenticator, delegateQueue: .main).dataTask(with: request) { data, response, error in
                
                if error != nil {
                    completion?(error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode) else {
                        
                        if let data = data,
                            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                            let reason = json["reason"] as? String
                        {
                            completion?(RuntimeError(reason))
                        }
                        else {
                            completion?(RuntimeError("Unknown error"))
                        }
                        return
                }
                
                completion?(nil)
                
            }.resume()
        } catch let error {
            debugPrint(error)
        }
    }
    
    private func baseURL(_ deviceId: String) -> String {
        if isProduction {
            return "https://api.push.apple.com:443/3/device/\(deviceId)"
        }
        
        return "https://api.sandbox.push.apple.com:443/3/device/\(deviceId)"
    }
    
    private func generateJwtToken() throws -> String {
        let timeInterval = Int64(Date().timeIntervalSince1970)
                
        
        let header = [
            "alg": "ES256",
            "kid": self.keyId
        ]
        
        let body = [
            "iss": self.teamId,
            "iat": "\(timeInterval)"
        ]
        
        func base64Encode(_ payload: [String: Any]) throws -> String {
            return try JSONSerialization.data(withJSONObject: payload, options: .init(rawValue: 0)).base64EncodedString()
        }
        
        let part = "\(try base64Encode(header)).\(try base64Encode(body))"
        let signature = try key.sign(part.data(using: .utf8)!).base64EncodedString()
        return "\(part).\(signature)"
    }
    
    private class PushAuthenticator: NSObject, URLSessionDelegate {
        private let key: Key
        init(key: Key) {
            self.key = key
            super.init()
        }
    
        public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
                    return completionHandler(.useCredential, nil)
            }

            completionHandler(.performDefaultHandling, nil)
        }
    }
}



class ViewController: UIViewController, UITextFieldDelegate {
    
    //MARK: Properties
    
    @IBOutlet weak var inProgressView: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var actionButton0: UIButton!
    @IBOutlet weak var actionButton1: UIButton!
    
    private static let bundleId = "com.XXXXXXXX.loopkit.Loop"
    private static let keyId = "XXXXXXXXX"//
    private static let teamId = "XXXXXXX"
    private static let deviceId = "xxxxxxxx"
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
       super.init(coder: aDecoder)
        Push.setup();
    }
    
    deinit {
        Push.cleanup()
    }
    
    var status = Status.newBolus
    
    override func viewDidLoad() {
        super.viewDidLoad()
        actionButton0.setTitle("NEW", for: .normal)
        actionButton1.isHidden = true
        amountTextField.smartInsertDeleteType = UITextSmartInsertDeleteType.no
        amountTextField.delegate = self
    }

    @IBAction func cancelRequest(_ sender: Any?) {
        inProgressView.isHidden = true
        status = Status.newBolusAmount
        action0(nil)
    }
    
    
    @IBAction func action0(_ sender: Any?) {
        switch status {
        case Status.newBolus: // new bolus, enter amount of insulin
            amountTextField.isUserInteractionEnabled = true
            amountTextField.becomeFirstResponder()
            actionButton0.setTitle("CANCEL", for: .normal)
            statusLabel.text = ""
            status = Status.newBolusAmount
        case Status.newBolusAmount: // cancel entering insulin
            amountTextField.resignFirstResponder()
            actionButton0.isHidden = false
            actionButton0.setTitle("NEW", for: .normal)
            amountTextField.text = ""
            actionButton1.isHidden = true
            amountTextField.isUserInteractionEnabled = false
            status = Status.newBolus
        default:
            print ("Unknown action")
        }
    }
    
    @IBAction func action1(_ sender: Any) {
        switch status {
        case Status.newBolusAmount: // send request to add bolus
            amountTextField.isUserInteractionEnabled = false
            amountTextField.resignFirstResponder()
            actionButton0.isHidden = true
            actionButton1.isHidden = true
            status = Status.setBolus
            inProgressView.isHidden = false
            do {
                try addBolus()
            }
            catch {
                print ("Error while adding bolus")
            }
        default:
            print ("Unknown action")
        }

    }
    
    
    
    func addBolus() throws {
        
        guard let amount = amountTextField.text, let bolus = Double(amount) else {
            throw T1DError.invalidAmount
        }

        let now = Date()
        let expire = Calendar.current.date(byAdding: .second, value: 60, to: now)
        let timeInterval = Int64(expire!.timeIntervalSince1970)
        
        let payload = [
        "aps": [
            "content-available": 1
        ],
        "bolus" : bolus,
        "timestamp": timeInterval
        ] as [String : Any]
        
        guard let tokenPath = Bundle.main.path(forResource: "Cert/AuthKey_\(ViewController.keyId)", ofType: "p8") else {
            return
        }
        
        let push = Push(bundleId: ViewController.bundleId,
                        keyId: ViewController.keyId,
                        teamId: ViewController.teamId,
                        key: try Key.loadPKCS8(tokenPath),
                        isProduction: false)

        push.push(deviceId: ViewController.deviceId, payload: payload, expiration: timeInterval) { error in
            
            guard let error = error else {
                self.statusLabel.text = "Bolus: \(bolus) has been sent!"
                return
            }
            
            
            if let error = error as? RuntimeError {
                self.statusLabel.text = error.localizedDescription
            }
            else {
                self.statusLabel.text = error.localizedDescription
            }
            
            self.cancelRequest(nil)
        }
        
        
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        var flag = true
        
        if range.location >= 3 { // max length is 3 (x.x)
            flag = false
        }
        else if range.location == 1 && range.length == 1 { // delete first digit
            textField.text = ""
            flag = false
        }
        else if range.location == 0 { // add first digit
            textField.text = string + "."
            flag = false
        }
        
        if range.location >= 2 && range.length == 0 {
            actionButton1.setTitle("ADD", for: .normal)
            actionButton1.isHidden = false
        }
        else {
            actionButton1.isHidden = true
        }
        
        return flag
    }
}

