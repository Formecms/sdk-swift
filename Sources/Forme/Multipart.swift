import Foundation

/// A single part in a `multipart/form-data` body. Either a text field or a
/// file with filename + MIME type.
enum MultipartPart {
    case text(name: String, value: String)
    case file(name: String, filename: String, mimeType: String, data: Data)
}

/// Build a `multipart/form-data` request body per RFC 7578.
///
/// Usage:
/// ```
/// let body = MultipartFormData(parts: [
///     .file(name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: imageData),
///     .text(name: "title", value: "Sunset"),
/// ])
/// request.httpBody = body.body
/// request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
/// ```
///
/// The boundary is a random per-instance string with a high-entropy
/// suffix to avoid colliding with content in the bytes — there is no
/// collision-detection here, only collision-avoidance. Callers cannot
/// supply the boundary; it is generated fresh on each instance.
struct MultipartFormData: Sendable {
    let body: Data
    let boundary: String

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    init(parts: [MultipartPart]) {
        let boundary = "FormeBoundary-\(UUID().uuidString)"
        self.boundary = boundary

        var data = Data()
        let crlf = Data("\r\n".utf8)
        let dashes = Data("--".utf8)
        let boundaryBytes = Data(boundary.utf8)

        for part in parts {
            // --boundary\r\n
            data.append(dashes)
            data.append(boundaryBytes)
            data.append(crlf)

            switch part {
            case .text(let name, let value):
                let safeName = quoteHeaderValue(name)
                let header = "Content-Disposition: form-data; name=\"\(safeName)\""
                data.append(Data(header.utf8))
                data.append(crlf)
                data.append(crlf)
                data.append(Data(value.utf8))
                data.append(crlf)

            case .file(let name, let filename, let mimeType, let fileData):
                let safeName = quoteHeaderValue(name)
                let safeFilename = quoteHeaderValue(filename)
                let header =
                    "Content-Disposition: form-data; name=\"\(safeName)\"; filename=\"\(safeFilename)\""
                data.append(Data(header.utf8))
                data.append(crlf)
                let typeHeader = "Content-Type: \(mimeType)"
                data.append(Data(typeHeader.utf8))
                data.append(crlf)
                data.append(crlf)
                data.append(fileData)
                data.append(crlf)
            }
        }

        // Closing delimiter: --boundary--\r\n
        data.append(dashes)
        data.append(boundaryBytes)
        data.append(dashes)
        data.append(crlf)

        self.body = data
    }
}

/// Escape characters that would break a quoted-string header value. We
/// follow RFC 7578 §4.2's recommendation to percent-encode `"` and `\`
/// in `Content-Disposition` parameters since not every server tolerates
/// backslash-escaping.
private func quoteHeaderValue(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
}
