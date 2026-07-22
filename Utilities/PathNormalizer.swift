import Foundation

enum PathNormalizer {
    static func normalize(_ path: String) -> String {
        let components = path.split(separator: "/").filter { $0 != "." && !$0.isEmpty }
        var result: [Substring] = []
        for component in components {
            if component == ".." {
                if !result.isEmpty { result.removeLast() }
            } else {
                result.append(component)
            }
        }
        return result.map(String.init).joined(separator: "/")
    }
}
