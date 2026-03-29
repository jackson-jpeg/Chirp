import SwiftUI
import PhotosUI

/// Source type for the image picker.
enum ImagePickerSource {
    case camera
    case library
}

/// Presents either ``PHPickerViewController`` (library) or
/// ``UIImagePickerController`` (camera) and returns a ``UIImage`` via callback.
struct ImagePickerView: UIViewControllerRepresentable {

    let source: ImagePickerSource
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .library:
            return makeLibraryPicker(context: context)
        case .camera:
            return makeCameraPicker(context: context)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - Library (PHPicker)

    private func makeLibraryPicker(context: Context) -> UIViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    // MARK: - Camera (UIImagePicker)

    private func makeCameraPicker(context: Context) -> UIViewController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let parent: ImagePickerView

        init(parent: ImagePickerView) {
            self.parent = parent
        }

        // PHPicker delegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                return
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onImagePicked(image)
                    }
                }
            }
        }

        // UIImagePicker delegate
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.dismiss()

            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
