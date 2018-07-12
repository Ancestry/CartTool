//
//  CartfileEntry.swift
//
//  Created by Bart Whiteley on 11/8/17.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation

struct CartfileEntry {
    var type: RepoType
    var repo: String
    var tag: String
    
    init?(line: String) {
        let tokens: [String] = line.components(separatedBy: .whitespacesAndNewlines)
        guard tokens.count == 3 else { return nil }
        guard let repoType = RepoType(rawValue: tokens[0]) else { return nil }
        type = repoType
        repo = tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        tag = tokens[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    
    var repoName: String {
        var repo = self.repo
        if repo.hasSuffix(".git") {
            let idx = repo.index(repo.endIndex, offsetBy: -4)
            repo = String(repo[..<idx])
        }
        let components = repo.components(separatedBy: "/")
        return components.last ?? repo
    }
    
    enum RepoType: String {
        case git = "git"
        case gitHub = "github"
    }
    
    var remoteURL: String {
        switch type {
        case .git:
            return repo
        case .gitHub:
            if URL(string: repo)?.host != nil {
                // GitHub enterprise entry
                return repo
            }
            else {
                return "https://github.com/\(repo).git"
            }
        }
    }
}

