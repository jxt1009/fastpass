import Foundation

extension Error {
    var diagnosticDescription: String {
        let nsError = self as NSError
        var result = nsError.localizedDescription
        result += " (\(nsError.domain) \(nsError.code))"
        if let urlString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
           let components = URLComponents(string: urlString) {
            let path = components.path
            let query = components.query.map { "?" + $0 } ?? ""
            if path != "/" {
                result += " \(path)\(query)"
            }
        }
        return result
    }
}
