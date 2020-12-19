//
//  AppStuff.swift
//  RemoteBolus
//
//  Created by Vladimir Tchernitski on 29.08.2020.
//  Copyright © 2020 Vladimir Tchernitski. All rights reserved.
//

import Foundation

enum Status {
    case newAction
    case newActionAmount
    case setAction
    case updateAction
    case deleteAction
}

enum T1DError: Error {
    case invalidAmount
}

class Credentials {
    static let bundleId = ""
    static let keyId = ""
    static let teamId = ""
    static let deviceId = ""
}

