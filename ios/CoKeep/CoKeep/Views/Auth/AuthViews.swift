import SwiftUI

struct AuthFlowView: View {
    @State private var mode: Mode = .welcome

    enum Mode {
        case welcome, login, register, forgot
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            AtmosphericBlobs()

            switch mode {
            case .welcome:
                WelcomeView(
                    onLogin: { withAnimation { mode = .login } },
                    onRegister: { withAnimation { mode = .register } }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .login:
                LoginView(
                    onBack: { withAnimation { mode = .welcome } },
                    onForgot: { withAnimation { mode = .forgot } },
                    onRegister: { withAnimation { mode = .register } }
                )
                .transition(.move(edge: .trailing))
            case .register:
                RegisterView(onBack: { withAnimation { mode = .welcome } })
                    .transition(.move(edge: .trailing))
            case .forgot:
                ForgotPasswordView(onBack: { withAnimation { mode = .login } })
                    .transition(.move(edge: .trailing))
            }
        }
    }
}

struct WelcomeView: View {
    var onLogin: () -> Void
    var onRegister: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("CoKeep")
                .font(Theme.brandFont(size: 52))
                .foregroundStyle(Theme.ink)
                .offset(y: appear ? 0 : 12)
                .opacity(appear ? 1 : 0)

            Text(L10n.string("welcome.headline"))
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
                .padding(.trailing, 40)
                .opacity(appear ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(L10n.string("welcome.getStarted"), action: onRegister)
                    .buttonStyle(PrimaryButtonStyle())
                Button(L10n.string("welcome.signIn"), action: onLogin)
                    .buttonStyle(PrimaryButtonStyle(filled: false))
            }
            .opacity(appear ? 1 : 0)
        }
        .padding(28)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    var onBack: () -> Void
    var onForgot: () -> Void
    var onRegister: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onBack) {
                    Label(L10n.string("common.back"), systemImage: "chevron.left")
                        .foregroundStyle(Theme.accent)
                }
                Text(L10n.string("login.title"))
                    .font(Theme.brandFont(size: 34))
                    .foregroundStyle(Theme.ink)

                FieldLabel(L10n.string("auth.email"))
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))

                FieldLabel(L10n.string("auth.password"))
                SecureField("", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))

                Button(L10n.string("login.forgot"), action: onForgot)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.accent)

                if let error {
                    Text(error).foregroundStyle(Theme.danger).font(.footnote)
                }

                Button(L10n.string("login.submit")) {
                    Task { await submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading)

                Button(L10n.string("login.needAccount"), action: onRegister)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
    }

    private func submit() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await session.login(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject private var session: SessionStore
    var onBack: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var country = CountryCode.common[0]
    @State private var phone = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    Label(L10n.string("common.back"), systemImage: "chevron.left")
                        .foregroundStyle(Theme.accent)
                }
                Text(L10n.string("register.title"))
                    .font(Theme.brandFont(size: 34))
                    .foregroundStyle(Theme.ink)
                Text(L10n.string("register.subtitle"))
                    .foregroundStyle(Theme.muted)
                    .font(.system(.body, design: .rounded))

                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        FieldLabel(L10n.string("auth.firstName"))
                        TextField("", text: $firstName)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                    }
                    VStack(alignment: .leading) {
                        FieldLabel(L10n.string("auth.lastName"))
                        TextField("", text: $lastName)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                    }
                }

                FieldLabel(L10n.string("auth.email"))
                TextField("", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))

                FieldLabel(L10n.string("auth.phone"))
                HStack(spacing: 8) {
                    Picker("", selection: $country) {
                        ForEach(CountryCode.common) { c in
                            Text("\(c.flag) \(c.code)").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))

                    TextField(L10n.string("auth.phonePlaceholder"), text: $phone)
                        .keyboardType(.phonePad)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                }

                FieldLabel(L10n.string("auth.password"))
                SecureField(L10n.string("auth.passwordHint"), text: $password)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))

                if let error {
                    Text(error).foregroundStyle(Theme.danger).font(.footnote)
                }

                Button(L10n.string("register.submit")) {
                    Task { await submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading || password.count < 5)
            }
            .padding(28)
        }
    }

    private func submit() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await session.register(
                firstName: firstName,
                lastName: lastName,
                email: email,
                countryCode: country.code,
                phone: phone,
                password: password
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ForgotPasswordView: View {
    @EnvironmentObject private var session: SessionStore
    var onBack: () -> Void
    @State private var email = ""
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onBack) {
                Label(L10n.string("common.back"), systemImage: "chevron.left")
                    .foregroundStyle(Theme.accent)
            }
            Text(L10n.string("forgot.title"))
                .font(Theme.brandFont(size: 34))
            Text(L10n.string("forgot.subtitle"))
                .foregroundStyle(Theme.muted)

            if sent {
                Text(L10n.string("forgot.sent"))
                    .foregroundStyle(Theme.accent)
            } else {
                TextField(L10n.string("auth.email"), text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                if let error { Text(error).foregroundStyle(Theme.danger).font(.footnote) }
                Button(L10n.string("forgot.submit")) {
                    Task {
                        do {
                            try await session.requestPasswordReset(email: email)
                            sent = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Spacer()
        }
        .padding(28)
    }
}

struct ResetPasswordView: View {
    @EnvironmentObject private var session: SessionStore
    let token: String
    @State private var password = ""
    @State private var confirm = ""
    @State private var done = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("CoKeep")
                    .font(Theme.brandFont(size: 28))
                Text(L10n.string("reset.title"))
                    .font(.title2.weight(.semibold))
                if done {
                    Text(L10n.string("reset.done"))
                    Button(L10n.string("welcome.signIn")) {
                        session.resetToken = nil
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    SecureField(L10n.string("auth.passwordHint"), text: $password)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                    SecureField(L10n.string("reset.confirm"), text: $confirm)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.85)))
                    if let error { Text(error).foregroundStyle(Theme.danger).font(.footnote) }
                    Button(L10n.string("reset.submit")) {
                        Task {
                            guard password.count >= 5, password == confirm else {
                                error = L10n.string("reset.mismatch")
                                return
                            }
                            do {
                                try await session.resetPassword(token: token, password: password)
                                done = true
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Spacer()
            }
            .padding(28)
        }
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.muted)
    }
}

struct AtmosphericBlobs: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: drift ? 40 : -20, y: drift ? -80 : -40)
            Circle()
                .fill(Theme.warm.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 35)
                .offset(x: drift ? -60 : -30, y: drift ? 220 : 180)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .allowsHitTesting(false)
    }
}
