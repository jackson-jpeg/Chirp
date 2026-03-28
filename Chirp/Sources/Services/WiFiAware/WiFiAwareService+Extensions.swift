#if canImport(WiFiAware)
import WiFiAware

extension WAPublishableService {
    static var chirpPTT: WAPublishableService {
        allServices["_chirp-ptt._udp"]!
    }
}

extension WASubscribableService {
    static var chirpPTT: WASubscribableService {
        allServices["_chirp-ptt._udp"]!
    }
}
#endif
