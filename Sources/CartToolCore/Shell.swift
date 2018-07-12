//
//  Shell.swift
//
//  Created by Bart Whiteley on 1/31/18.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation

@discardableResult
func ishell(env: [String: String]? = nil, _ args: String...) -> Int32 {
    return runShell(env: env, args: args)
}

func shell(env: [String: String]? = nil, _ args: String...) throws {
    let rv = runShell(env: env, args: args)
    if rv != 0 {
        throw "\(args[0]) terminated with \(rv)"
    }
}

func shellOutput(env: [String: String]? = nil, _ args: String...) throws -> String {
    return try runShellWithOutput(env: env, args: args)
}

// https://stackoverflow.com/questions/26971240/how-do-i-run-an-terminal-command-in-a-swift-script-e-g-xcodebuild
private func runShell(env: [String: String]?, args: [String]) -> Int32 {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = args
    if let env = env {
        task.environment = env
    }
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
}

// https://stackoverflow.com/questions/26971240/how-do-i-run-an-terminal-command-in-a-swift-script-e-g-xcodebuild/39364135#39364135
private func runShellWithOutput(env: [String: String]?, args: [String]) throws -> String {
    let task = Process()
    let pipe = Pipe()
    task.launchPath = "/usr/bin/env"
    task.arguments = args
    task.standardOutput = pipe
    if let env = env {
        task.environment = env
    }
    
    task.launch()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)
    task.waitUntilExit()
    
    let rv = task.terminationStatus
    guard rv == 0 else { throw "\(args[0]) terminated with \(rv)" }
    guard let theRealOutput = output else { throw "Could not parse output." }
    
    return theRealOutput
}
