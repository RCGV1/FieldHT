import XCTest
@testable import FieldHT

final class RepeaterBookServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSearchByCallsignBuildsAuthenticatedRequest() async throws {
        let service = makeService(token: " rbuapp_test_token ")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/export.php")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-RB-App-Token"), "rbuapp_test_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "FieldHTTests/1.0")

            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "callsign" })?.value, "W1AW")

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("""
                {
                  "count": "1",
                  "results": [
                    {
                      "Frequency": "146.940000",
                      "Input Freq": "146.340000",
                      "PL": "100.0",
                      "Callsign": "W1AW"
                    }
                  ]
                }
                """.utf8)
            )
        }

        let results = try await service.searchByCallsign(" w1aw ")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].callsign, "W1AW")
        XCTAssertEqual(results[0].frequencyMHz, 146.94)
        XCTAssertEqual(results[0].inputFreqMHz, 146.34)
        XCTAssertEqual(results[0].subAudio, .frequency(100.0))
    }

    func testSearchRepeatersUsesStateIDForNorthAmerica() async throws {
        let service = makeService(token: "rbuapp_test_token")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/export.php")

            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "state_id" })?.value, "06")
            XCTAssertNil(components?.queryItems?.first(where: { $0.name == "state" }))
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "city" })?.value, "Los Angeles")

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"count":0,"results":[]}"#.utf8)
            )
        }

        let results = try await service.searchRepeaters(
            country: "United States",
            state: "06",
            city: "Los Angeles"
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchRepeatersUsesROWEndpointOutsideNorthAmerica() async throws {
        let service = makeService(token: "rbuapp_test_token")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/exportROW.php")

            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "country" })?.value, "Switzerland")

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"count":0,"results":[]}"#.utf8)
            )
        }

        _ = try await service.searchRepeaters(country: "Switzerland", state: nil, city: nil)
    }

    func testMissingTokenFailsBeforeNetworkRequest() async {
        let service = makeService(token: " ")
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Service should not call the network without an API token")
            throw URLError(.badServerResponse)
        }

        do {
            _ = try await service.searchByCallsign("W1AW")
            XCTFail("Expected missing token error")
        } catch let error as RepeaterBookError {
            XCTAssertEqual(error, .missingAPIToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIErrorDecodesRepeaterBookMessage() async {
        let service = makeService(token: "rbuapp_test_token")

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"ok":false,"error_code":"auth_missing","message":"Authorization required."}"#.utf8)
            )
        }

        do {
            _ = try await service.searchByCallsign("W1AW")
            XCTFail("Expected RepeaterBook API error")
        } catch let error as RepeaterBookError {
            XCTAssertEqual(
                error,
                .apiError(statusCode: 401, errorCode: "auth_missing", message: "Authorization required.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService(token: String?) -> RepeaterBookService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        return RepeaterBookService(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://www.repeaterbook.com/api/export.php")!,
            rowBaseURL: URL(string: "https://www.repeaterbook.com/api/exportROW.php")!,
            userAgent: "FieldHTTests/1.0",
            tokenProvider: { token }
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
