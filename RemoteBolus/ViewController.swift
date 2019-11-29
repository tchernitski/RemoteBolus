//
//  ViewController.swift
//  RemoteBolus
//
//  Created by Vladimir Tchernitski on 02/04/2019.
//  Copyright © 2019 Vladimir Tchernitski. All rights reserved.
//

import UIKit

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

class ViewController: UIViewController, UITextFieldDelegate {
    
    //MARK: Properties
    
    @IBOutlet weak var inProgressView: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var actionButton0: UIButton!
    @IBOutlet weak var actionButton1: UIButton!
    
    private static let bundleId = "com.XXXXXXXXX.loopkit.Loop"
    private static let keyId = "XXXXXXXXXv"
    private static let teamId = "XXXXXXXXX"
    private static let deviceId = "XXXXXXXXX"
    
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
                self.statusLabel.text = "Bolus \(bolus) has been sent!"
                self.cancelRequest(nil)
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
