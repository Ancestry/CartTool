import CartToolCore
import Foundation

let tool = CartTool()

do {
    try tool.run()
} catch {
    print("error: \(error)")
    exit(EXIT_FAILURE)
}

