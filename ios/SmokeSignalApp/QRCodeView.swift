import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

#if canImport(UIKit)
import UIKit
#endif

final class QRCodeRenderer {
    static let shared = QRCodeRenderer()

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    func render(code: String, correctionLevel: String = "L", scale: CGFloat = 10) -> UIImage? {
        #if canImport(UIKit)
        filter.message = Data(code.utf8)
        filter.correctionLevel = correctionLevel
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
        #else
        return nil
        #endif
    }
}

struct QRCodeView: View {
    let code: String

    var body: some View {
        #if canImport(UIKit)
        if let image = QRCodeRenderer.shared.render(code: code) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .background(.white)
        } else {
            Color.gray
        }
        #else
        Text("QR rendering requires UIKit")
        #endif
    }
}

