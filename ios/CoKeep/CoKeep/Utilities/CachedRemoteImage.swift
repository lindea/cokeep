import SwiftUI
import UIKit

/// Loads a remote image through `ImageCache`, refetching only when the URL changes.
struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                uiImage = nil
                return
            }
            // Keep the previous image visible while a new URL downloads.
            let image = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            uiImage = image
        }
    }
}
