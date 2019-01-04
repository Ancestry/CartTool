//
//  XcodeProj.swift
//
//  Created by Bart Whiteley 
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//


@testable import CartToolCore
import XCTest


class CartToolTests: XCTestCase {
    func testCartfileLineParsing() throws {
        let line = "git \"ssh://git@stash.test.com:7999/migf/apicore.git\" \"1.1.0\""
        let entry: CartfileEntry = try unwrap(CartfileEntry(line: line))
        XCTAssertEqual(entry.type, CartfileEntry.RepoType.git)
        XCTAssertEqual("apicore", entry.repoName)
        XCTAssertEqual("ssh://git@stash.test.com:7999/migf/apicore.git", entry.remoteURL)
        XCTAssertEqual("1.1.0", entry.tag)
    }
    
    func testCartfileParsing() throws {
        let file = """
github "utahiosmac/Marshal" "7a814e26312d5e7f1209168ca1a7860dcc12cf5f"
github "pluralsight/PSOperations" "785cf88eb3b6fcce4c2d7ecdb231067b8c832baf"
github "antitypical/Result" "d7f10e2b1745d189434d262072fac764c3021ba8"
git "http://stash01.test.com/scm/mif/acextensionkit.git" "e68966e063d84a70044f2945f9d05af1909e5797"
git "http://stash/scm/mntv/native-tree-viewer.git" "1.5.2"
git "http://stash01.test.com/scm/mif/acrestkit.git" "ed6f61fa144d3e2291b700227f7af1a58293a2f7"
git "http://stash01.test.com/scm/mif/treekit.git" "4fcb19deba5c5379086dc4f5c8a8c8d5164c46ad"
git "http://stash01.test.com/scm/mif/acapikit.git" "f2625df41ff4b0f33d9d21e3ba412cf6b84d204d"
"""
        let checkout = CartTool()
        let lines = checkout.cartFileLines(fileContents: file)
        let entries = lines.compactMap(CartfileEntry.init)
        XCTAssertEqual(entries[1].repoName, "PSOperations")
        XCTAssertEqual(8, entries.count)
        XCTAssertEqual(CartfileEntry.RepoType.git, entries[7].type)
        XCTAssertEqual(CartfileEntry.RepoType.gitHub, entries[1].type)
        XCTAssertEqual("native-tree-viewer", entries[4].repoName)
        XCTAssertNotNil(URL(string: entries[4].remoteURL))
        XCTAssertEqual("treekit", entries[6].repoName)
        XCTAssertEqual("Result", entries[2].repoName)
        XCTAssertNotNil(URL(string: entries[0].remoteURL))
        XCTAssertEqual("https://github.com/utahiosmac/Marshal.git", entries[0].remoteURL)
    }
        
    func testEnvVarSplitter() {
        let escapedValue = "/Users/foo/Library/DerivedData/Debug-iphonesimulator /Users/foo/code/IOS\\ Project/Source/Carthage/Build/iOS"
        
        let ra = splitEnvVar(escapedValue)
        XCTAssertEqual(2, ra.count)
        XCTAssertEqual(ra[0], "/Users/foo/Library/DerivedData/Debug-iphonesimulator")
        XCTAssertEqual(ra[1], "/Users/foo/code/IOS Project/Source/Carthage/Build/iOS")
    }
    
    func testGetDependencies() {
        let projectPath = Path(#file).parent.parent.pathByAppending(component: "Resources")
        let appPath = projectPath.pathByAppending(component: "TestApp.app/TestApp")
        let frameworksPath = projectPath.pathByAppending(component: "Carthage/Build/iOS")
        
        setenv("FRAMEWORK_SEARCH_PATHS", frameworksPath.absolute, 1)
        let expected: Set<String> = ["SwiftBits.framework", "FBSDKLoginKit.framework", "FBSDKCoreKit.framework", "Bolts.framework"]
        
        do {
            let result = try Set(getDependencies(appPath: appPath).map { $0.baseName })
            XCTAssertEqual(expected, result)
        }
        catch {
            XCTFail("getDependencies threw error: \(error)")
        }
    }
    
    func testPathWithSymlink() {
        let basePath = Path(#file).parent.parent.pathByAppending(component: "Resources")
        let symlink = basePath.pathByAppending(component: "SwiftBits.framework").absolute
        let expected = basePath.pathByAppending(component: "Carthage/Build/iOS/SwiftBits.framework").absolute
        
        let result = Path(symlink).absolute
        
        XCTAssertEqual(result, expected)
    }
    
    func testRemoveLastPathComponent() {
        let expected = "/Carthage/Build/iOS/Result.framework"
        let path = Path(expected + "/Result")
        let result = path.removeLastPathComponent().absolute
        
        XCTAssertEqual(expected, result)
    }
}

func unwrap<T>(_ opt: Optional<T>) throws -> T {
    guard let value = opt else { throw "Expected .some" }
    return value
}
