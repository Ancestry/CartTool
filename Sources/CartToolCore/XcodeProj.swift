//
//  XcodeProj.swift
//
//  Created by Bart Whiteley on 1/28/18.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation

/**
 This is intended to be executed as a Run Script build phase in Xcode.
 Extracts the list of frameworks from the Link Binary with Libraries build phase of the current target.
 Searches for each framework in FRAMEWORK_SEARCH_PATHS.
 Sets up input and output environment variables for each framework, and invokes `carthage copy-frameworks`.
 
 throws: String error if carthage is not installed or an expected environment variable is missing.
 */
func wrapCarthageCopyFrameworks() throws {
    guard ishell("which", "carthage") == 0 else {
        throw "carthage executable not found"
    }
    
    let builtProductsDir = try getEnv("BUILT_PRODUCTS_DIR")
    let frameworksFolderPath = try getEnv("FRAMEWORKS_FOLDER_PATH")
    let executableName = try getEnv("EXECUTABLE_NAME")
    let appPath = Path(builtProductsDir)
        .pathByAppending(component: "\(executableName).app")
        .pathByAppending(component: executableName)
    let frameworksTargetDir = Path(builtProductsDir).pathByAppending(component: frameworksFolderPath)
    
    let inputs = try getDependencies(appPath: appPath)
    let outputs = inputs.map {
        frameworksTargetDir.pathByAppending(component: $0.baseName)
    }
    
    print("Resolved frameworks for `carthage copy-frameworks`:")
    inputs.forEach { print($0.absolute) }
    
    let fm = FileManager.default
    let inputsOutputs: [(Path, Path)] = zip(inputs, outputs).compactMap { inOut in
        let sourceAttributes = try? fm.attributesOfItem(atPath: inOut.0.absolute)
        let destAttributes = try? fm.attributesOfItem(atPath: inOut.1.absolute)
        if let sourceModDate = sourceAttributes?[.modificationDate] as? Date,
            let destModDate = destAttributes?[.modificationDate] as? Date,
            sourceModDate <= destModDate {
            print("Skipping \(inOut.0.absolute) (\(sourceModDate)) because it is not newer than \(inOut.1.absolute) (\(destModDate))")
            return nil
        }
        
        return inOut
    }

    var env: [String: String] = ProcessInfo.processInfo.environment
    for (idx, inOut) in inputsOutputs.enumerated() {
        let iKey = "SCRIPT_INPUT_FILE_\(idx)"
        env[iKey] = inOut.0.absolute
        let oKey = "SCRIPT_OUTPUT_FILE_\(idx)"
        env[oKey] = inOut.1.absolute
    }
    let countString = String(inputsOutputs.count)
    env["SCRIPT_INPUT_FILE_COUNT"] = countString
    env["SCRIPT_OUTPUT_FILE_COUNT"] = countString
    
    if !inputsOutputs.isEmpty {
        try shell(env: env, "carthage", "copy-frameworks")
    }
}

/// Generates a set of direct and transitive dependencies for a compiled iOS app using otool.
///
/// - Parameters:
///   - appPath: The file path to the compiled app.
///   - frameworksPath: The file path to the directory containing the compiled framework dependencies.
/// - Returns: A set of strings representing all the dependencies for a compiled app.
internal func getDependencies(appPath: Path) throws -> Set<Path> {
    var dependenciesToProcess = try resolve(frameworks: otool(path: appPath))
    var dependencies: Set<Path> = []
    
    while !dependenciesToProcess.isEmpty {
        guard let next = dependenciesToProcess.popFirst() else { break }
        guard !dependencies.contains(next) else { continue }
        
        dependencies.insert(next)
        let newDependencies = try resolve(frameworks: otool(path: next))
        dependenciesToProcess.formUnion(newDependencies)
    }
    
    // Strip the executable name from the framework as Carthage only wants up to the .framework
    return Set(dependencies.map { $0.removeLastPathComponent() })
}

private func otool(path: Path) -> Set<String> {
    do {
        let output = try shellOutput("otool", "-L", path.absolute)
        let frameworks = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "(").first! }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("@rpath") }
            .filter { !$0.contains("libswift") }
            .map { $0.replacingOccurrences(of: "@rpath/", with: "") }
        
        return Set(frameworks)
    } catch {
        print("Failed to get otool output from \(path)")
        return []
    }
}

private func frameworkNames(from paths: [Path]) -> [String] {
    return paths.compactMap { $0.baseName.components(separatedBy: ".").first }
}

/**
 Turn a space-delimited string into an array separated by spaces
 - parameter str: The input string
 - returns: Array of strings produced by splitting the input on spaces
 
 Note: spaces not intended to be used as separated should be escaped as "\\ "
 (this is how Xcode excapes spaces in path elements for environment variables such as FRAMEWORK_SEARCH_PATHS)
 */
internal func splitEnvVar(_ str: String) -> [String] {
    let escapedSpacePlaceholder: StringLiteralType = "_escaped_space_placeholder_"
    let tmp = str.replacingOccurrences(of: "\\ ", with: escapedSpacePlaceholder)
    return tmp.split(separator: " ").map(String.init).map { str in
        str.replacingOccurrences(of: escapedSpacePlaceholder, with: " ")
    }
}

/**
 Get an environment variable
 - parameter key: The name of the environment variable to retrieve
 - throws: String error if the variable is not found
 - returns: Value of the environment variable
 */
private func getEnv(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key] else {
        throw "Missing \(key) environment variable"
    }
    return value
}

/**
 Search for frameworks in FRAMEWORK_SEARCH_PATHS
 
 - parameter Frameworks: The list of framework names
 - throws: String error if a framework is not found in FRAMEWORK_SEARCH_PATHS
 - returns: Array of full paths to frameworks found in FRAMEWORK_SEARCH_PATHS
 */
private func resolve(frameworks: Set<String>) throws -> Set<Path> {
    let fm = FileManager.default
    let frameworkSearchPathsVar = try getEnv("FRAMEWORK_SEARCH_PATHS")
    let frameworkSearchPaths: [String] = splitEnvVar(frameworkSearchPathsVar)

    return Set(try frameworks.map { framework in
        for path in frameworkSearchPaths {
            let fullFrameworkPath = Path(path).pathByAppending(component: framework).absolute
            if fm.fileExists(atPath: fullFrameworkPath) {
                return Path(fullFrameworkPath)
            }
        }
        throw "Unable to find \(framework) in FRAMEWORK_SEARCH_PATHS"
    })
}
