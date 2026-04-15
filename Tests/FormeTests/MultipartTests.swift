import Testing
import Foundation
@testable import Forme

@Suite("MultipartFormData — RFC 7578 body construction")
struct MultipartTests {
    @Test func emptyPartsListProducesClosingBoundaryOnly() {
        let m = MultipartFormData(parts: [])
        let s = String(decoding: m.body, as: UTF8.self)
        #expect(s == "--\(m.boundary)--\r\n")
        #expect(m.contentType == "multipart/form-data; boundary=\(m.boundary)")
    }

    @Test func singleTextPartHasCorrectFraming() {
        let m = MultipartFormData(parts: [.text(name: "title", value: "Hello")])
        let s = String(decoding: m.body, as: UTF8.self)

        let expected =
            "--\(m.boundary)\r\n" +
            "Content-Disposition: form-data; name=\"title\"\r\n" +
            "\r\n" +
            "Hello\r\n" +
            "--\(m.boundary)--\r\n"
        #expect(s == expected)
    }

    @Test func singleFilePartHasContentTypeHeader() {
        let bytes = Data([0x42, 0x43, 0x44])
        let m = MultipartFormData(parts: [
            .file(name: "file", filename: "x.bin", mimeType: "application/octet-stream", data: bytes),
        ])
        let s = String(decoding: m.body, as: UTF8.self)
        #expect(s.contains("Content-Disposition: form-data; name=\"file\"; filename=\"x.bin\"\r\n"))
        #expect(s.contains("Content-Type: application/octet-stream\r\n"))
        #expect(s.hasSuffix("--\(m.boundary)--\r\n"))
    }

    @Test func multipleMixedPartsAllPresentInOrder() {
        let m = MultipartFormData(parts: [
            .file(name: "file", filename: "p.jpg", mimeType: "image/jpeg", data: Data([0x01])),
            .text(name: "title", value: "A"),
            .text(name: "alt", value: "B"),
        ])
        let s = String(decoding: m.body, as: UTF8.self)

        guard
            let fileRange = s.range(of: "name=\"file\""),
            let titleRange = s.range(of: "name=\"title\""),
            let altRange = s.range(of: "name=\"alt\"")
        else {
            Issue.record("Missing one or more parts in body")
            return
        }
        #expect(fileRange.lowerBound < titleRange.lowerBound)
        #expect(titleRange.lowerBound < altRange.lowerBound)
    }

    @Test func boundaryIsUniqueAcrossInstances() {
        let a = MultipartFormData(parts: [.text(name: "x", value: "1")])
        let b = MultipartFormData(parts: [.text(name: "x", value: "1")])
        #expect(a.boundary != b.boundary)
    }

    @Test func filenameWithQuotesAndBackslashesEscaped() {
        let m = MultipartFormData(parts: [
            .file(name: "file", filename: "weird\"name\\.jpg", mimeType: "image/jpeg", data: Data()),
        ])
        let s = String(decoding: m.body, as: UTF8.self)
        // Backslash and quote must be escaped to keep quoted-string framing intact.
        #expect(s.contains("filename=\"weird\\\"name\\\\.jpg\""))
    }

    @Test func filenameStripsCRLFInjection() {
        // Defends against header-injection via filename. The literal
        // sequence `\r\n<header-name>:` must NOT survive into the body —
        // otherwise an attacker-controlled filename could inject MIME
        // headers (or worse, smuggle a body part).
        let m = MultipartFormData(parts: [
            .file(name: "file", filename: "evil\r\nX-Injected: 1.jpg", mimeType: "image/jpeg", data: Data()),
        ])
        let s = String(decoding: m.body, as: UTF8.self)
        #expect(!s.contains("\r\nX-Injected"))
        #expect(s.contains("filename=\"evilX-Injected: 1.jpg\""))
    }

    @Test func binaryBytesPreservedExactly() {
        let bytes = Data((0...255).map { UInt8($0) })
        let m = MultipartFormData(parts: [
            .file(name: "file", filename: "bin", mimeType: "application/octet-stream", data: bytes),
        ])
        // Locate the file's body by finding the double-CRLF after its
        // Content-Type line, then read up to the next CRLF + boundary.
        let body = m.body
        let crlfcrlf = Data("\r\n\r\n".utf8)
        let boundaryClose = Data("\r\n--\(m.boundary)--\r\n".utf8)
        guard
            let startMarkerRange = body.range(of: crlfcrlf),
            let endMarkerRange = body.range(of: boundaryClose)
        else {
            Issue.record("Missing markers")
            return
        }
        let bodyStart = startMarkerRange.upperBound
        let extracted = body.subdata(in: bodyStart..<endMarkerRange.lowerBound)
        #expect(extracted == bytes)
    }
}
