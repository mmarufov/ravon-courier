import SwiftUI
import UIKit
import RavonCore

// MARK: - Hand-to-me delivery code pad

struct DeliveryCodePadView: View {
    @Binding var code: String
    @Binding var attempts: Int
    @Binding var showError: Bool
    @State private var shake = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Введите код от клиента")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("0000", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .frame(width: 140)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .offset(x: shake ? -8 : 0)
                .animation(
                    showError ? .default.repeatCount(3, autoreverses: true).speed(4) : .default,
                    value: shake
                )
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    code = String(digits.prefix(4))
                    showError = false
                }
                .onChange(of: showError) { _, new in
                    if new {
                        shake.toggle()
                    }
                }

            if showError {
                Text(attempts >= 3
                     ? "Попросите клиента посмотреть код в чате доставки."
                     : "Неверный код от клиента")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Leave-at-door photo picker (camera)

struct PhotoProofPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.delegate = context.coordinator
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.cameraCaptureMode = .photo
        p.allowsEditing = false
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoProofPicker

        init(_ parent: PhotoProofPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - JPEG compression to ≤ 500 KB

enum DeliveryProofImage {
    static let maxBytes = 500 * 1024

    /// Compress until under the cap. Returns nil only if the image can't fit even at 0.1 quality.
    static func compress(_ image: UIImage) -> Data? {
        var quality: CGFloat = 0.85
        while quality >= 0.1 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return nil
    }
}
