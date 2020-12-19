//
//  RootViewController.swift
//  RemoteBolus
//
//  Created by Vladimir Tchernitski on 29.08.2020.
//  Copyright © 2020 Vladimir Tchernitski. All rights reserved.
//

import UIKit


class RootViewController: UITableViewController {
    
    @IBOutlet weak var turnOnLoop: UISwitch!
    @IBOutlet weak var suspendDelivery: UISwitch!
    
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if userAlreadyExist(key: "closedLoop") {
            turnOnLoop.isOn = UserDefaults.standard.bool(forKey: "closedLoop")
        }
        if userAlreadyExist(key: "suspendDelivery") {
            suspendDelivery.isOn = UserDefaults.standard.bool(forKey: "suspendDelivery")
        }
        else {
            suspendDelivery.isOn = false
        }
    }
    
    func userAlreadyExist(key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) != nil
    }
    
    @IBAction func loopAction(sender: AnyObject) {

        let closedLoop = self.turnOnLoop.isOn
        
        do {
            try updateLoopStatus(value: closedLoop)
        }
        catch {
            print ("Error while closing/opening loop")
        }
    }
    
    @IBAction func suspendAction(sender: AnyObject) {

        let suspendDelivery = self.suspendDelivery.isOn
        
        do {
            try updateSuspendStatus(value: suspendDelivery)
        }
        catch {
            print ("Error while closing/opening loop")
        }
    }
    
    func updateSuspendStatus(value: Bool) throws {
        
        let now = Date()
        let expire = Calendar.current.date(byAdding: .second, value: 60, to: now)
        let timeInterval = Int64(expire!.timeIntervalSince1970)
        
        let payload = [
        "aps": [
            "content-available": 1
        ],
        "suspend" : value,
        "timestamp": timeInterval
        ] as [String : Any]
        
        guard let tokenPath = Bundle.main.path(forResource: "Cert/AuthKey_\(Credentials.keyId)", ofType: "p8") else {
            return
        }
        
        let push = Push(bundleId: Credentials.bundleId,
                        keyId: Credentials.keyId,
                        teamId: Credentials.teamId,
                        key: try Key.loadPKCS8(tokenPath),
                        isProduction: false)

        push.push(deviceId: Credentials.deviceId, payload: payload, expiration: timeInterval) { error in
            
            guard error != nil else {
                UserDefaults.standard.set(value, forKey: "suspendDelivery") //Bool
                return
            }
            
            self.suspendDelivery.isOn = !value
        }
    }
    
    func updateLoopStatus(value: Bool) throws {
        
        let now = Date()
        let expire = Calendar.current.date(byAdding: .second, value: 60, to: now)
        let timeInterval = Int64(expire!.timeIntervalSince1970)
        
        let payload = [
        "aps": [
            "content-available": 1
        ],
        "loop" : value,
        "timestamp": timeInterval
        ] as [String : Any]
        
        guard let tokenPath = Bundle.main.path(forResource: "Cert/AuthKey_\(Credentials.keyId)", ofType: "p8") else {
            return
        }
        
        let push = Push(bundleId: Credentials.bundleId,
                        keyId: Credentials.keyId,
                        teamId: Credentials.teamId,
                        key: try Key.loadPKCS8(tokenPath),
                        isProduction: false)

        push.push(deviceId: Credentials.deviceId, payload: payload, expiration: timeInterval) { error in
            
            guard error != nil else {
                UserDefaults.standard.set(value, forKey: "closedLoop") //Bool
                return
            }
            
            self.turnOnLoop.isOn = !value
        }
    }

}
