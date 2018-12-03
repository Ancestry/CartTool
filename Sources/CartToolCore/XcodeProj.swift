//
//  XcodeProj.swift
//
//  Created by Bart Whiteley on 1/28/18.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation
import xcproj

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
    
    let xcodeProjPath = try getEnv("PROJECT_FILE_PATH")
    let targetName = try getEnv("TARGET_NAME")
    let builtProductsDir = try getEnv("BUILT_PRODUCTS_DIR")
    let frameworksFolderPath = try getEnv("FRAMEWORKS_FOLDER_PATH")
    
    let carthageFrameworks = try getCarthageFrameworks(target: targetName, xcodeprojFolder: xcodeProjPath)
    
    let frameworksTargetDir = Path(builtProductsDir).pathByAppending(component: frameworksFolderPath)
    
    let inputs = try resolve(frameworks: carthageFrameworks)
    let outputs = carthageFrameworks.map {
        frameworksTargetDir.pathByAppending(component: $0).absolute
    }
    
    print("Resolved frameworks for `carthage copy-frameworks`:")
    inputs.forEach { print($0) }
    
    let fm = FileManager.default
    let inputsOutputs: [(String, String)] = try zip(inputs, outputs).compactMap { inOut in
        let sourceAttributes = try fm.attributesOfItem(atPath: inOut.0)
        let destAttributes = try fm.attributesOfItem(atPath: inOut.1)
        if let sourceModDate = sourceAttributes[.modificationDate] as? Date,
            let destModDate = destAttributes[.modificationDate] as? Date,
            sourceModDate <= destModDate {
            print("Skipping \(inOut.0) (\(sourceModDate)) because it is not newer than \(inOut.1) (\(destModDate))")
            return nil
        }
        
        return inOut
    }

    var env: [String: String] = ProcessInfo.processInfo.environment
    for (idx, inOut) in inputsOutputs.enumerated() {
        let iKey = "SCRIPT_INPUT_FILE_\(idx)"
        env[iKey] = inOut.0
        let oKey = "SCRIPT_OUTPUT_FILE_\(idx)"
        env[oKey] = inOut.1
    }
    let countString = String(inputsOutputs.count)
    env["SCRIPT_INPUT_FILE_COUNT"] = countString
    env["SCRIPT_OUTPUT_FILE_COUNT"] = countString
    
    if !inputsOutputs.isEmpty {
        try shell(env: env, "carthage", "copy-frameworks")
    }
    
    try wrapVerifyDependencies()
}

/**
 This is run as part of `carttool copy-frameworks` and should only be used as a separate build phase if the former is not used.
 Recursively runs `otool -L` on the app and all dependent frameworks.
 Verifies that all transitive dependencies are explicitly included as app dependent frameworks.
 
 throws: String error if a dependency is missing or an expected environment variable is missing.
 */
func wrapVerifyDependencies() throws {
    let builtProductsDir = try getEnv("BUILT_PRODUCTS_DIR")
    let frameworksFolderPath = try getEnv("FRAMEWORKS_FOLDER_PATH")
    let appPath = Path(builtProductsDir).pathByAppending(component: frameworksFolderPath).parent.absolute
    
    try verifyDependencies(appPath: Path(appPath))
}

internal func verifyDependencies(appPath: Path) throws {
    print("Verifying dependencies...")
    
    guard let appName = appPath.baseName.components(separatedBy: ".").first else { throw "Invalid app path." }
    
    let frameworksPath = appPath.pathByAppending(component: "Frameworks")
    
    var frameworksToProcess = otool(path: appPath.pathByAppending(component: appName))
    var alreadyProcessed: Set<String> = []
    var allFrameworks = frameworksToProcess
    
    while !frameworksToProcess.isEmpty {
        guard let next = frameworksToProcess.popLast() else { break }
        guard !alreadyProcessed.contains(next) else { continue }
        
        alreadyProcessed.insert(next)
        let newFrameworks = otool(path: frameworksPath.pathByAppending(component: next))
        frameworksToProcess += newFrameworks
        allFrameworks += newFrameworks
    }
    
    let actualFrameworks = try! FileManager.default.contentsOfDirectory(atPath: frameworksPath.absolute)
    let actualNames = Set(frameworkNames(from: actualFrameworks.map { Path($0) }))
    let expectedNames = Set(frameworkNames(from: allFrameworks.map { Path($0) }))
    
    let remaining = expectedNames.subtracting(actualNames)
    if remaining.isEmpty {
        print("Dependencies check out. Nothing to see here.")
    } else {
        throw "Missing dependent framework(s): " + remaining.joined(separator: ", ")
    }
}

private func otool(path: Path) -> [String] {
    do {
        let output = try shellOutput("otool", "-L", path.absolute)
        let frameworks = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "(").first! }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("@rpath") }
            .filter { !$0.contains("libswift") }
            .map { $0.replacingOccurrences(of: "@rpath/", with: "") }
        
        return frameworks
    } catch {
        print("Failed to get otool output from \(path)")
        return []
    }
}

private func frameworkNames(from paths: [Path]) -> [String] {
    return paths.compactMap { $0.baseName.components(separatedBy: ".").first }
}

/**
 Return the frameworks from the Link Binary with Libraries build phase of a given target.
 The frameworks are filtered based on a source tree type of Source Root, and the
 presense of "Carthage/Build" in the path.
 
 - parameter target: The name of the current target
 - parameter xcodeprojFolder: The path to the <project>.xcodeproj folder
 - throws: String error if something goes wrong while traversing objects in the project
 - returns: Array of framework names (without paths)
 */
internal func getCarthageFrameworks(target targetName: String, xcodeprojFolder: String) throws -> [String] {
    let project = try XcodeProj(pathString: xcodeprojFolder)
    let objects = project.pbxproj.objects
    let targets = objects.targets(named: targetName)
    guard targets.count == 1, let target = targets.first else {
        throw "Project does not contain exactly one target named \(targetName)"
    }

    let frameworkPhasesIds: [String] = target.object.buildPhases.filter { phaseId in
        return objects.frameworksBuildPhases.contains(reference: phaseId)
    }
    
    guard frameworkPhasesIds.count == 1, let frameworkPhaseId = frameworkPhasesIds.first else {
        throw "Target \(targetName) does not contain exactly one Frameworks build phase"
    }

    guard let frameworkPhase: PBXFrameworksBuildPhase = objects.frameworksBuildPhases[frameworkPhaseId] else {
        throw "Target \(targetName) has frameworks build phase \(frameworkPhasesIds) but no such phase exists"
    }
    
    let fileRefs: [PBXFileReference] = try frameworkPhase.files.map { fileId in
        guard let refId = objects.buildFiles[fileId]?.fileRef else {
            throw "No file ref for fileId \(fileId)"
        }
        guard let fileRef = objects.getFileElement(reference: refId) as? PBXFileReference else {
            throw "Missing fileRef or invalid type for file ref Id \(refId)"
        }
        return fileRef
    }
    
    let filtered: [String] = fileRefs.compactMap { fileRef in
        guard fileRef.sourceTree == .sourceRoot || fileRef.sourceTree == .group else { return nil }
        guard let name = fileRef.name else { return nil }
        guard let path = fileRef.path else { return nil }
        guard path.contains("Carthage/Build") else { return nil }
        return name
    }
    return filtered
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
internal func getEnv(_ key: String) throws -> String {
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
internal func resolve(frameworks: [String]) throws -> [String] {
    let fm = FileManager.default
    let frameworkSearchPathsVar = try getEnv("FRAMEWORK_SEARCH_PATHS")
    let frameworkSearchPaths: [String] = splitEnvVar(frameworkSearchPathsVar)
    return try frameworks.map { framework in
        for path in frameworkSearchPaths {
            let fullFrameworkPath = Path(path).pathByAppending(component: framework).absolute
            if fm.fileExists(atPath: fullFrameworkPath) {
                return fullFrameworkPath
            }
        }
        throw "Unable to find \(framework) in FRAMEWORK_SEARCH_PATHS"
    }
}

internal func extractProjectsFrom(xcworkspacePath: String) throws -> [String] {
    let workspace = try XCWorkspace(pathString: xcworkspacePath).data
    var projects: [String] = []
    let refs = workspace.children
    
    for ref in refs {
        switch ref {
        case .file(let file):
            let pathStr = file.location.path
            if pathStr.hasSuffix(".xcodeproj") &&
                !pathStr.contains("Carthage/Checkouts") { // ignore the project's dependencies
                let workspaceParentFolder = Path(xcworkspacePath).parent
                projects.append(workspaceParentFolder.pathByAppending(component: pathStr).absolute)
            }
        default:
            break
        }
    }
    
    return projects
}

