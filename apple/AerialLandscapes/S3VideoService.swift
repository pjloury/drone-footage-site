import Foundation
import CommonCrypto
import AVFoundation
import UIKit

enum VideoFetchResult {
    case success([Video])
    case failure(Error)
}

class S3VideoService: ObservableObject {
    let s3Service: S3Service
    @Published private(set) var remoteVideos: [Video] = []
    
    init() {
        self.s3Service = S3Service(
            accessKey: AWSCredentials.accessKey,
            secretKey: AWSCredentials.secretKey,
            region: AWSCredentials.region,
            bucketName: AWSCredentials.bucketName
        )
    }
    
    func fetchAvailableVideos(completion: @escaping (Result<[Video], Error>) -> Void) {
        print("\n=== 📱 Fetching Available S3 Videos ===")
        s3Service.listObjects { result in
            switch result {
            case .success(let videos):
                print("\n📹 Found \(videos.count) videos in S3:")
                videos.forEach { video in
                    print("✅ Video: \(video.displayTitle)")
                    print("   Path: \(video.remoteVideoPath ?? "nil")")
                }
                completion(.success(videos))
            case .failure(let error):
                print("❌ Failed to fetch videos: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    func generateSignedRequest(for video: Video) -> URLRequest {
        guard let remoteURL = video.remoteVideoURL else {
            fatalError("Attempted to generate signed request for video without remote URL: \(video.displayTitle)")
        }
        return s3Service.generateSignedRequest(for: remoteURL)
    }
    
    func generateSignedRequest(for url: URL) -> URLRequest {
        return s3Service.generateSignedRequest(for: url)
    }
    
    func getThumbnailURL(for uuid: String) -> URL? {
        let urlString = "https://\(s3Service.bucketName).s3.\(s3Service.region).amazonaws.com/\(uuid).jpg"
        return URL(string: urlString)
    }
}

// S3Service implementation
class S3Service {
    public let bucketName: String
    public let region: String
    private let accessKey: String
    private let secretKey: String
    
    init(accessKey: String, secretKey: String, region: String, bucketName: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.bucketName = bucketName
    }
    
    func listObjects(completion: @escaping (Result<[Video], Error>) -> Void) {
        let timestamp = getCurrentAWSTimestamp()
        let host = "\(bucketName).s3.\(region).amazonaws.com"
        let endpoint = "https://\(host)/"
        
        // Use just list-type=2 for now
        let queryString = "list-type=2"
        guard let url = URL(string: "\(endpoint)?\(queryString)") else {
            completion(.failure(NSError(domain: "S3Service", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(timestamp.amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        
        // Match the canonical request exactly
        let canonicalRequest = [
            "GET",
            "/",
            "list-type=2",
            "host:\(host)",
            "x-amz-content-sha256:UNSIGNED-PAYLOAD",
            "x-amz-date:\(timestamp.amzDate)",
            "",
            "host;x-amz-content-sha256;x-amz-date",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(timestamp.dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = """
        \(algorithm)
        \(timestamp.amzDate)
        \(credentialScope)
        \(sha256(canonicalRequest))
        """
        
        let kDate = hmac(key: "AWS4\(secretKey)".data(using: .utf8)!, data: timestamp.dateStamp)
        let kRegion = hmac(key: kDate, data: region)
        let kService = hmac(key: kRegion, data: "s3")
        let kSigning = hmac(key: kService, data: "aws4_request")
        let signature = hmac(key: kSigning, data: stringToSign).hexEncodedString()
        
        let authorizationHeader = """
        \(algorithm) \
        Credential=\(accessKey)/\(credentialScope), \
        SignedHeaders=host;x-amz-content-sha256;x-amz-date, \
        Signature=\(signature)
        """
        
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        // Log request headers
        print("\n📤 Request Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            print("\(key): \(value)")
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("\n❌ Network Error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("\n📥 Response Status: \(httpResponse.statusCode)")
                print("Response Headers:")
                httpResponse.allHeaderFields.forEach { key, value in
                    print("\(key): \(value)")
                }
            }
            
            if let data = data {
                print("\n📦 Response Data:")
                if let xmlString = String(data: data, encoding: .utf8) {
                    print(xmlString)
                }
                
                let parser = XMLParser(data: data)
                let delegate = S3ParserDelegate(bucketName: self.bucketName, region: self.region)
                parser.delegate = delegate
                
                if parser.parse() {
                    print("\n✅ Successfully parsed XML response")
                    print("Found \(delegate.videos.count) videos")
                    
                    // Create a dispatch group to wait for all metadata fetches
                    let group = DispatchGroup()
                    var videosWithMetadata: [Video] = []
                    
                    for video in delegate.videos {
                        group.enter()
                        self.getObjectMetadata(for: video) { result in
                            switch result {
                            case .success(let updatedVideo):
                                videosWithMetadata.append(updatedVideo)
                                print("✅ Updated metadata for: \(updatedVideo.displayTitle)")
                            case .failure(let error):
                                print("❌ Failed to fetch metadata for \(video.displayTitle): \(error)")
                                videosWithMetadata.append(video)
                            }
                            group.leave()
                        }
                    }
                    
                    // Wait for all metadata fetches to complete
                    group.notify(queue: .main) {
                        print("\n✅ Completed metadata fetch for all videos")
                        completion(.success(videosWithMetadata))
                    }
                } else {
                    print("\n❌ Failed to parse XML response")
                    if let error = parser.parserError {
                        print("Parser error: \(error)")
                    }
                    completion(.failure(NSError(domain: "S3Service", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML response"])))
                }
            } else {
                print("\n❌ No data received from S3")
                completion(.failure(NSError(domain: "S3Service", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
            }
        }
        
        task.resume()
    }
    
    func generateSignedRequest(for url: URL) -> URLRequest {
        let host = "\(bucketName).s3.\(region).amazonaws.com"
        let timestamp = getCurrentAWSTimestamp()
        let amzDate = timestamp.amzDate
        let dateStamp = timestamp.dateStamp
        
        // Get the URI-encoded path component
        let path = url.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        
        let canonicalRequest = [
            "GET",
            encodedPath,
            "",
            "host:\(host)",
            "x-amz-content-sha256:UNSIGNED-PAYLOAD",
            "x-amz-date:\(amzDate)",
            "",
            "host;x-amz-content-sha256;x-amz-date",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = """
        \(algorithm)
        \(amzDate)
        \(credentialScope)
        \(sha256(canonicalRequest))
        """
        
        let kDate = hmac(key: "AWS4\(secretKey)".data(using: .utf8)!, data: dateStamp)
        let kRegion = hmac(key: kDate, data: region)
        let kService = hmac(key: kRegion, data: "s3")
        let kSigning = hmac(key: kService, data: "aws4_request")
        let signature = hmac(key: kSigning, data: stringToSign).hexEncodedString()
        
        let authorizationHeader = "\(algorithm) " +
            "Credential=\(accessKey)/\(credentialScope)," +
            "SignedHeaders=host;x-amz-content-sha256;x-amz-date," +
            "Signature=\(signature)"
        
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func getCurrentAWSTimestamp() -> (amzDate: String, dateStamp: String) {
        let currentDate = Date()
        
        let amzDateFormatter = ISO8601DateFormatter()
        amzDateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        amzDateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = amzDateFormatter.string(from: currentDate)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: currentDate)
        
        return (amzDate, dateStamp)
    }
    
    private func sha256(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func hmac(key: Data, data: String) -> Data {
        let strData = data.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            strData.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                      keyPtr.baseAddress, key.count,
                      dataPtr.baseAddress, strData.count,
                      &hash)
            }
        }
        return Data(hash)
    }
    
    func getThumbnailURL(for uuid: String) -> URL? {
        let urlString = "https://\(bucketName).s3.\(region).amazonaws.com/\(uuid).jpg"
        return URL(string: urlString)
    }
    
    func getObjectMetadata(for video: Video, completion: @escaping (Result<Video, Error>) -> Void) {
        guard let remoteURL = video.remoteVideoURL else {
            print("❌ No remote URL for video: \(video.displayTitle)")
            completion(.failure(NSError(domain: "S3Service", code: -1, userInfo: [NSLocalizedDescriptionKey: "No remote URL"])))
            return
        }
        
        print("\n🔍 Making HEAD request for: \(video.displayTitle)")
        print("URL: \(remoteURL)")
        
        let timestamp = getCurrentAWSTimestamp()
        let host = "\(bucketName).s3.\(region).amazonaws.com"
        
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(timestamp.amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        
        // Log the request headers
        print("\n📤 HEAD Request Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            print("\(key): \(value)")
        }
        
        // Add authorization header
        let canonicalRequest = [
            "HEAD",
            remoteURL.path,
            "",
            "host:\(host)",
            "x-amz-content-sha256:UNSIGNED-PAYLOAD",
            "x-amz-date:\(timestamp.amzDate)",
            "",
            "host;x-amz-content-sha256;x-amz-date",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(timestamp.dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = """
        \(algorithm)
        \(timestamp.amzDate)
        \(credentialScope)
        \(sha256(canonicalRequest))
        """
        
        let kDate = hmac(key: "AWS4\(secretKey)".data(using: .utf8)!, data: timestamp.dateStamp)
        let kRegion = hmac(key: kDate, data: region)
        let kService = hmac(key: kRegion, data: "s3")
        let kSigning = hmac(key: kService, data: "aws4_request")
        let signature = hmac(key: kSigning, data: stringToSign).hexEncodedString()
        
        let authorizationHeader = "\(algorithm) " +
            "Credential=\(accessKey)/\(credentialScope)," +
            "SignedHeaders=host;x-amz-content-sha256;x-amz-date," +
            "Signature=\(signature)"
        
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ HEAD request failed: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                completion(.failure(NSError(domain: "S3Service", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            print("\n📥 HEAD Response for \(video.displayTitle):")
            print("Status: \(httpResponse.statusCode)")
            print("\nAll Headers:")
            httpResponse.allHeaderFields.forEach { key, value in
                print("\(key): \(value)")
            }
            
            // Extract metadata from headers
            for (key, value) in httpResponse.allHeaderFields {
                let keyString = String(describing: key).lowercased()
                print("Header: \(keyString) = \(value)")
            }
            
            // Look for our metadata headers
            var displayTitle = ""
            var geozone = ""
            
            for (key, value) in httpResponse.allHeaderFields {
                let keyString = String(describing: key).lowercased()
                if keyString == "x-amz-meta-display-title" {
                    displayTitle = String(describing: value)
                    print("📝 Found display title: \(displayTitle)")
                } else if keyString == "x-amz-meta-geozone" {
                    geozone = String(describing: value)
                    print("🌍 Found geozone: \(geozone)")
                }
            }
            
            // Create updated video with metadata
            var updatedVideo = video
            if !displayTitle.isEmpty {
                updatedVideo = Video(
                    id: video.id,
                    displayTitle: displayTitle,
                    geozone: geozone.isEmpty ? video.geozone : geozone,
                    remoteVideoPath: video.remoteVideoPath,
                    remoteThumbnailPath: video.remoteThumbnailPath,
                    localVideoPath: video.localVideoPath,
                    localThumbnailPath: video.localThumbnailPath,
                    isSelected: video.isSelected
                )
            }
            
            completion(.success(updatedVideo))
        }
        
        task.resume()
    }
}

// S3ParserDelegate implementation
private class S3ParserDelegate: NSObject, XMLParserDelegate {
    private let bucketName: String
    private let region: String
    var videos: [Video] = []
    
    private var currentElement: String = ""
    private var currentKey: String = ""
    private var currentDisplayTitle: String = ""
    private var currentGeozone: String = ""
    private var isInMetadata = false
    private var currentMetadataKey: String = ""
    
    init(bucketName: String, region: String) {
        self.bucketName = bucketName
        self.region = region
        super.init()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "Key":
            currentKey = ""
        case "UserMetadata":
            isInMetadata = true
            currentDisplayTitle = ""
            currentGeozone = ""
        case "x-amz-meta-display-title", "x-amz-meta-geozone":
            if isInMetadata {
                currentMetadataKey = elementName
            }
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        if currentElement == "Key" {
            currentKey = trimmedString
            print("📄 Found key: \(trimmedString)")
        } else if isInMetadata {
            switch currentMetadataKey {
            case "x-amz-meta-display-title":
                currentDisplayTitle = trimmedString
                print("📝 Found display title: \(trimmedString)")
            case "x-amz-meta-geozone":
                currentGeozone = trimmedString
                print("🌍 Found geozone: \(trimmedString)")
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Contents" {
            if currentKey.hasSuffix(".mp4") || currentKey.hasSuffix(".mov") {
                let baseFilename = currentKey.components(separatedBy: ".").first ?? currentKey
                
                // Use .jpg extension for remote thumbnails
                let remoteThumbnailPath = "\(baseFilename).jpg"
                // Keep _thumbnail suffix for local thumbnails
                let localThumbnailPath = "Thumbnails/\(baseFilename)_thumbnail.jpg"
                
                // Create Video using S3 metadata
                let finalDisplayTitle = currentDisplayTitle.isEmpty ? baseFilename : currentDisplayTitle
                
                // Ensure geozone is lowercase and defaults to "international" if empty
                let finalGeozone = currentGeozone.isEmpty ? "international" : currentGeozone.lowercased()
                
                let video = Video(
                    id: baseFilename,
                    displayTitle: finalDisplayTitle,
                    geozone: finalGeozone,
                    remoteVideoPath: currentKey,
                    remoteThumbnailPath: remoteThumbnailPath,
                    localVideoPath: nil,
                    localThumbnailPath: localThumbnailPath,
                    isSelected: false
                )
                videos.append(video)
                
                print("\n📼 Parsed video: \(video.displayTitle)")
                print("   Video URL: \(video.remoteVideoURL?.absoluteString ?? "nil")")
                print("   Remote Thumbnail Path: \(remoteThumbnailPath)")
                print("   Remote Thumbnail URL: \(video.remoteThumbnailURL?.absoluteString ?? "nil")")
                print("   Local Thumbnail Path: \(localThumbnailPath)")
                print("   Geozone: \(video.geozone)")
                print("   S3 Metadata - Display Title: \(currentDisplayTitle)")
                print("   S3 Metadata - Geozone: \(currentGeozone)")
            }
            
            // Reset for next item
            currentKey = ""
            currentDisplayTitle = ""
            currentGeozone = ""
            isInMetadata = false
            currentMetadataKey = ""
        } else if elementName == "UserMetadata" {
            isInMetadata = false
            print("- Display Title: '\(currentDisplayTitle)'")
            print("- Geozone: '\(currentGeozone)'")
        }
        
        currentElement = ""
    }
}

private extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

