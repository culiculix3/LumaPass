import AuthenticationServices
import SwiftUI

struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let onSignIn: (String?, String?, Error?) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let token = credential.identityToken,
                    let tokenString = String(data: token, encoding: .utf8)
                else {
                    onSignIn(nil, nil, AppleSignInError.missingIdentityToken)
                    return
                }
                let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                onSignIn(tokenString, name.isEmpty ? nil : name, nil)
            case let .failure(error):
                onSignIn(nil, nil, error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Iniciar sesión con Apple")
    }
}

private enum AppleSignInError: LocalizedError {
    case missingIdentityToken

    var errorDescription: String? {
        "Apple no devolvió un token de identidad válido."
    }
}
