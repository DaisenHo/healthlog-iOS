import Foundation

#if canImport(UserNotifications) && canImport(UIKit)

    /// #141 / #126 3.2 — where a plain tap on a push lands when no earlier
    /// branch of `dispatchAction` claimed it (mood reminder, preventive-care
    /// reminder, a medication with its id).
    ///
    /// The server's top-level `url` wins: every visible push carries one since
    /// v1.43, and a Guardian or discreet delivery carries `/` so it opens home.
    /// The older `deepLink` (only local banners still set it) is the fallback.
    extension NotificationService {
        /// What a body tap opens.
        enum BodyTapTarget: Equatable {
            case route(DeepLinkRoute)
            case link(URL)
        }

        nonisolated static func bodyTapTarget(for payload: APNsPayload) -> BodyTapTarget? {
            if let path = payload.url {
                return .route(DeepLinkRoute.fromPushPath(path))
            }
            return payload.deepLink.map(BodyTapTarget.link)
        }

        @MainActor
        func routeBodyTap(_ payload: APNsPayload) {
            switch Self.bodyTapTarget(for: payload) {
            case let .route(route): deepLinks.handle(route)
            case let .link(url): deepLinks.handle(url)
            case nil: break
            }
        }
    }

#endif
