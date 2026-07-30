// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - QRCodeView

/// Renders a string (here an `otpauth://` URI) as a scannable QR code. Uses CoreImage, which is
/// available on both iOS and macOS, so the same view serves every native client.
struct QRCodeView: View {

    // MARK: Static Properties

    /// Shared across renders: `CIContext` compiles and allocates render resources on creation, so
    /// reusing one instance instead of allocating a fresh context per image avoids repeating that
    /// cost every time this view (re-)renders.
    private static let context = CIContext()

    // MARK: Properties

    let string: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if let image = Self.makeImage(from: string) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Static Functions

    private static func makeImage(from string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            return nil
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        return context.createCGImage(scaled, from: scaled.extent)
    }
}

#if DEBUG
    #Preview {
        QRCodeView(string: "otpauth://totp/Stash:otavio?secret=JBSWY3DPEHPK3PXP&issuer=Stash")
            .frame(width: 180, height: 180)
            .padding()
    }
#endif
