//
//  CartTool.swift
//
//  Created by Bart Whiteley on 11/8/17.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation
import Utility
import Basic
import AppKit

public final class CartTool {
    private var arguments: [String]
    
    fileprivate let checkoutsDir = Path("Carthage/Checkouts")
    
    public init(arguments: [String] = CommandLine.arguments) { 
        self.arguments = arguments
    }

    public func run() throws {
        let parser = ArgumentParser(commandName: nil,
                                    usage: "<sub-command> ...",
                                    overview: "Utility for managing Carthage dependencies")
        
        do {
            let checkoutParser = parser.add(subparser: "checkout", overview: "Checkout a Carthage dependency for development.")
            let checkoutRepo = checkoutParser.add(positional: "repo", kind: String.self)
            let checkoutFolder = checkoutParser.add(positional: "folder", kind: String.self, optional: true, usage: "Destination folder", completion: .filename)
            
            let mkworkspaceParser = parser.add(subparser: "mkworkspace",
                                               overview: "Create a workspace with the current project and Carthage dependencies.")
            let workspaceName = mkworkspaceParser.add(positional: "workspace-name", kind: String.self)
            let workspaceRepos = mkworkspaceParser.add(positional: "repos", kind: [String].self, optional: true)
            
            _ = parser.add(subparser: "verify-dependencies", overview: "Verify that all required frameworks are properly embedded in the project. Intended to be used in an Xcode Run Script.")
            _ = parser.add(subparser: "list", overview: "List dependencies.")
            _ = parser.add(subparser: "copy-frameworks", overview: "Used as an Xcode Run Script.")
            _ = parser.add(subparser: "version", overview: "Prints the current version number of carttool.")
            
            let args = Array(CommandLine.arguments.dropFirst())
            let result = try parser.parse(args)
            
            guard let subcommand = result.subparser(parser) else {
                parser.printUsage(on: stdoutStream)
                throw ""
            }
            
            switch subcommand {
            case "verify-dependencies":
                try wrapVerifyDependencies()
            case "copy-frameworks":
                try wrapCarthageCopyFrameworks()
            case "list":
                try printRepoList()
            case "checkout":
                let repo = result.get(checkoutRepo)!
                let folder = result.get(checkoutFolder)
                try checkout(repo: repo, destination: folder)
            case "mkworkspace":
                let name = result.get(workspaceName)!
                let repos: [String] = result.get(workspaceRepos) ?? []
                
                try mkworkspace(name: name, repos: repos)
            case "version":
                printVersion()
            default:
                break
            }
            
        }
        catch let error as ArgumentParserError {
            print(error.description)
            parser.printUsage(on: stdoutStream)
        }
        catch {
            throw error
        }
    }
    
    func printVersion() {
        print(CartToolVersion.current)
    }
    
    func checkout(repo: String, destination: String? = nil) throws {
        guard let entry = try cartfileEntry(forRepo: repo) else { throw "Can't find Cartfile entry for \(repo)" }
        let destDir: Path
        if let _dest = destination {
            destDir = Path(_dest)
        }
        else {
            destDir = checkoutsDir
        }
        try checkout(entry: entry, in: destDir)
    }
    
    func checkout(entry: CartfileEntry, in folder: Path) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.absolute) else { throw "Error: \(folder) does not exist" }
        let cwd = fm.currentDirectoryPath
        defer { fm.changeCurrentDirectoryPath(cwd) }
        
        let repoPath = folder.pathByAppending(component: entry.repoName)
        let inContext: Bool = repoPath.absolute.hasPrefix(checkoutsDir.absolute)
        
        var tempDirectoryForOldCheckouts: TemporaryDirectory?
        
        if inContext {
            let oldCheckouts = repoPath.pathByAppending(component: "Carthage/Checkouts")
            // Copy the symlinks under Carthage/Checkouts so we can restore them
            // in the new sandbox. We copy them to a temporary directory rather
            // than moving the old checkout, so we can move the checkout to trash
            // properly (including preserving the correct original location).
            if fm.fileExists(atPath: oldCheckouts.absolute) {
                let temp = try TemporaryDirectory(removeTreeOnDeinit: true)
                try shell("cp", "-a", oldCheckouts.absolute, temp.path.asString)
                tempDirectoryForOldCheckouts = temp
            }
            try moveCheckoutToTrash(entry: entry)
        }
        
        
        fm.changeCurrentDirectoryPath(folder.absolute)
        try shell("git", "clone", entry.remoteURL)
        fm.changeCurrentDirectoryPath(repoPath.absolute)
        try shell("git", "checkout", entry.tag)
        
        if inContext {
            try shell("mkdir", "-p", "Carthage")
            let carthageBuildPath = Path(cwd).pathByAppending(component: "Carthage/Build")
            try shell("ln", "-s", carthageBuildPath.absolute, "Carthage/Build")
            if let tempDirectory = tempDirectoryForOldCheckouts {
                let backupFolder = Path(tempDirectory.path.asString)
                let oldCheckouts = backupFolder.pathByAppending(component: "Checkouts")
                let newCheckoutsFolder = repoPath.pathByAppending(component: "Carthage/Checkouts")
                try shell("cp", "-a", oldCheckouts.absolute, newCheckoutsFolder.absolute)
            }
        }
    }
    
    func moveCheckoutToTrash(entry: CartfileEntry) throws {
        // can't get NSWorkspace.shared.recycle to work syncronously
        NSWorkspace.shared.performFileOperation(.recycleOperation, source: checkoutsDir.absolute, destination: "", files: [entry.repoName], tag: nil)
    }

    func cartfileEntry(forRepo repoName: String) throws -> CartfileEntry? {
        return try cartfileEntries()
            .first { entry in
                return entry.repoName.lowercased() == repoName.lowercased()
            }
    }
    
    func printRepoList() throws {
        for entry in try cartfileEntries() {
            let line = "\(entry.repoName) \(entry.remoteURL) \(entry.tag)"
            print(line)
        }
    }
    
    func readCartfileResolved() throws -> String {
        let dir = FileManager.default.currentDirectoryPath
        let filePath = dir + "/Cartfile.resolved"
        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        return contents
    }
    
    func cartfileEntries() throws -> [CartfileEntry] {
        return try cartFileLines(fileContents: readCartfileResolved()).compactMap(CartfileEntry.init)
    }
    
    func cartFileLines(fileContents: String) -> [String] {
        return fileContents
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
    }
    
    func mkworkspace(name: String, repos: [String]) throws {
        let workspaceDir = Path(name + ".xcworkspace")
        let contentsFile = workspaceDir.pathByAppending(component: "contents.xcworkspacedata")
        
        let repoNames: [String]
        if repos.count > 0 {
            repoNames = try properCaseRepoNames(forRepos: repos)
        }
        else {
            repoNames = try cartfileEntries().map { $0.repoName }
        }
        
        try shell("mkdir", "-p", workspaceDir.absolute)
        
        let fm = FileManager.default
        
        var projectFiles: [String] = []
        
        for repo in repoNames {
            let folder = Path("Carthage/Checkouts").pathByAppending(component: repo)
            let dotGit = folder.pathByAppending(component: ".git")
            guard fm.fileExists(atPath: folder.absolute) else {
                print("Skipping \(repo): no sources found. Need to checkout first?")
                continue
            }
            if !fm.fileExists(atPath: dotGit.absolute) {
                makeFolderReadOnly(folder)
            }
            projectFiles += try projectsWithin(folder: folder)
        }
        
        projectFiles.sort { (l, r) in
            return Path(l).baseName.lowercased() < Path(r).baseName.lowercased()
        }
        
        var fileContents: String = ""
        fileContents += """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace
            version = "1.0">
        
        """
        let localProjects: [String] = try fm.contentsOfDirectory(atPath: fm.currentDirectoryPath).filter{ $0.hasSuffix(".xcodeproj") }
        
        for project in localProjects {
            fileContents += """
                <FileRef
                    location = "group:\(project)">
                </FileRef>
            
            """
        }
        
        fileContents += """
            <Group
                location = "container:"
                name = "Dependencies">
        
        """
        
        for project in projectFiles {
            fileContents += """
                    <FileRef
                        location = "group:\(project)">
                    </FileRef>
            
            """
        }
        fileContents += """
            </Group>
        </Workspace>
        
        """
        
        let url = URL(fileURLWithPath: contentsFile.absolute, isDirectory: false)
        try fileContents.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func makeFolderReadOnly(_ path: Path) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path.absolute) else { return }
        
        for item in enumerator {
            guard let file = item as? String else { continue }
            let filePath = path.pathByAppending(component: file)
            guard let attrs = enumerator.fileAttributes else { continue }
            guard let type:String = attrs[.type] as? String else { continue }
            guard type == "NSFileTypeRegular" else { continue }
            guard isSourceFile(file) else { continue }
            chmod(filePath.absolute, 0o444)
        }
    }
    
    func projectsWithin(folder: Path) throws -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: folder.absolute) else {
            throw "Failed to enumerate folder \(folder.absolute)"
        }
        
        var projects: [String] = []
        
        // first look for a workspace
        if let workspaceFolder = try fm.contentsOfDirectory(atPath: folder.absolute).first(where: { $0.hasSuffix(".xcworkspace") }) {
            projects = try extractProjectsFrom(xcworkspacePath: folder.pathByAppending(component: workspaceFolder).absolute)
                .filter { try projectHasSharedSchemes(projectFolder: Path($0)) }
        }
        
        if projects.count > 0 {
            return projects
        }
        
        for item in try fm.contentsOfDirectory(atPath: folder.absolute) {
            let projectPath = folder.pathByAppending(component: item)
            if try item.hasSuffix(".xcodeproj") && projectHasSharedSchemes(projectFolder: projectPath) {
                projects.append(projectPath.absolute)
            }
        }
        
        if projects.count > 0 {
            return projects // don't go deep if there are top-level projects
        }
        
        for item in enumerator {
            guard let file = item as? String else { continue }
            let filePath = folder.pathByAppending(component: file)
            if try filePath.absolute.hasSuffix(".xcodeproj") && projectHasSharedSchemes(projectFolder: filePath) {
                projects.append(filePath.absolute)
            }
        }
        return projects
    }
    
    func projectHasSharedSchemes(projectFolder folder: Path) throws -> Bool {
        let fm = FileManager.default
        let schemesDir = folder.pathByAppending(component: "xcshareddata/xcschemes")
        if fm.fileExists(atPath: schemesDir.absolute) {
            if try fm.contentsOfDirectory(atPath: schemesDir.absolute).count > 0 {
                return true
            }
        }
        return false
    }
    
    func isSourceFile(_ filename: String) -> Bool {
        // TODO revisit this. should we make everything read-only?
        let exts: [String] = [".m", ".h", ".mm", ".cpp", ".c", ".cc", ".swift", ".xcconfig"]
        for ext in exts {
            if filename.hasSuffix(ext) { return true }
        }
        return false
    }
    
    func properCaseRepoNames(forRepos repos:[String]) throws -> [String] {
        var propers:[String] = []
        for repo in repos {
            guard let entry = try cartfileEntry(forRepo: repo) else {
                throw "Can't find Cartfile entry for " + repo
            }
            propers.append(entry.repoName)
        }
        return propers
    }
    
}



extension String: Error {}



