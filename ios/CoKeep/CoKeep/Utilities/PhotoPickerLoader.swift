import Foundation
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

extension PhotosPickerItem {
    /// Loads picked photo bytes and re-encodes as JPEG for upload.
    /// `loadTransferable(type: Data.self)` alone often returns nil for HEIC/library assets.
    func jpegDataForUpload(quality: CGFloat = 0.85) async throws -> Data {
        if let transferred = try await loadTransferable(type: PhotoTransferData.self),
           let jpeg = PhotoTransferData.jpegFromRaw(transferred.data, quality: quality) {
            return jpeg
        }

        if let raw = try await loadTransferable(type: Data.self),
           let jpeg = PhotoTransferData.jpegFromRaw(raw, quality: quality) {
            return jpeg
        }

        throw APIError.message(L10n.string("objects.photoLoadFailed"))
    }
}

private struct PhotoTransferData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PhotoTransferData(data: data)
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            PhotoTransferData(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            PhotoTransferData(data: data)
        }
        DataRepresentation(importedContentType: UTType("public.heic")!) { data in
            PhotoTransferData(data: data)
        }
    }

    static func jpegFromRaw(_ data: Data, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1600
        let scaled = scale(image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: quality)
    }

    private static func scale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
