import PassKit
import SwiftUI
import UIKit

struct WalletAddPassView: UIViewControllerRepresentable {
    let passData: Data
    let onCompletion: (PKPass, Bool) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let pass: PKPass
        do {
            pass = try PKPass(data: passData)
        } catch {
            notifyFailure("El archivo recibido no es un pase Wallet válido: \(error.localizedDescription)")
            return unavailableController(message: "El pase recibido no es válido.")
        }
        guard PKAddPassesViewController.canAddPasses(),
              let controller = PKAddPassesViewController(pass: pass)
        else {
            notifyFailure("Apple Wallet no está disponible en este dispositivo.")
            return unavailableController(message: "Apple Wallet no está disponible.")
        }
        controller.delegate = context.coordinator
        context.coordinator.pass = pass
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    private func notifyFailure(_ message: String) {
        DispatchQueue.main.async { onFailure(message) }
    }

    private func unavailableController(message: String) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
        ])
        return controller
    }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onCompletion: (PKPass, Bool) -> Void
        var pass: PKPass?

        init(onCompletion: @escaping (PKPass, Bool) -> Void) {
            self.onCompletion = onCompletion
        }

        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self, let controller else { return }
                if let pass = self.pass {
                    self.onCompletion(pass, PKPassLibrary().containsPass(pass))
                }
                controller.dismiss(animated: true)
            }
        }
    }
}
