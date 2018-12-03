//
//  CartToolVersion.swift
//
//  Created by David Boothe on 2/9/18.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation

struct CartToolVersion {
    let major: Int
    let minor: Int
    let patch: Int
    
    static let current: CartToolVersion = CartToolVersion(major: 1, minor: 0, patch: 4)
}

extension CartToolVersion: CustomStringConvertible {
    var description: String {
        return "\(major).\(minor).\(patch)"
    }
}
