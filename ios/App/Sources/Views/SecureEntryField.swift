import SwiftUI
import UIKit

/// The password field of the unlock flow (PLAN.md section 3): a UIKit secure field with
/// paste, drag and drop, the edit menu, AutoFill suggestions and autocorrection turned
/// off. Characters arrive one at a time, so neither a pasted nor an auto-filled password
/// gets in.
struct SecureEntryField: UIViewRepresentable {
    @Binding var text: String
    var placeholder = "Password"
    var isEnabled = true
    /// Change this value to put the cursor back in the field.
    var focusRequest = 0
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> LockedTextField {
        let field = LockedTextField()
        field.isSecureTextEntry = true
        // Not a password type, so iOS does not offer saved passwords in the keyboard bar.
        field.textContentType = .oneTimeCode
        field.placeholder = placeholder
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.inlinePredictionType = .no
        field.keyboardType = .default
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = true
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.clearsOnBeginEditing = false
        field.pasteConfiguration = nil
        field.textDropDelegate = context.coordinator
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.accessibilityLabel = placeholder
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return field
    }

    func updateUIView(_ field: LockedTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.isEnabled = isEnabled
        if isEnabled, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UITextDropDelegate {
        var parent: SecureEntryField
        var lastFocusRequest = Int.min

        init(_ parent: SecureEntryField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        /// One character at a time: refuses pasted text, AutoFill and dictation results.
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            string.count <= 1
        }

        func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
            UITextDropProposal(operation: .forbidden)
        }
    }
}

/// A text field with no edit menu (so no Paste, also not through ⌘V on a hardware
/// keyboard) and no three-finger editing gestures.
final class LockedTextField: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override var editingInteractionConfiguration: UIEditingInteractionConfiguration {
        .none
    }
}
