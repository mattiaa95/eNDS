//
//  PurchaseView.swift
//  eNDS
//
//  Ported from iGBA's redesigned paywall (GBA-Emu repo,
//  App/SwiftUI/Modules/PurchaseView/PurchaseView.swift) — same structure and
//  the same non-negotiable rules (each one a lesson from a real App Review
//  rejection or a real pricing complaint, per iGBA's own comments):
//   - Prices always come from StoreKit; the plan selector shows a loading
//     placeholder (never a hardcoded price) until `PurchaseModel` has real,
//     localized `displayPrice` values.
//   - Yearly is always preselected, by its explicit product id
//     ("iNDSPROYearly") — never `productIds.last`, which would silently
//     preselect the lifetime unlock once it becomes visible.
//   - Lifetime surfaces only where it is genuinely the better fit
//     (`shouldOfferLifetime`) — everyone else sees a pure subscription
//     paywall, plus a "See all plans" reveal.
//   - Zero invented reviews/badges/testimonials.
//   - Restore Purchases + tappable Privacy Policy and Terms of Use (Apple's
//     standard EULA, since eNDS has no custom one) + an auto-renewal /
//     cancel-anytime disclosure under the CTA.
//
//  Adaptations vs. iGBA:
//   - Brand gradient uses eNDS's own crimson (`Color.indsCrimsonLight` /
//     `indsCrimsonDark`, from SplashScreenView.swift) instead of iGBA's
//     orange/red, for visual continuity with eNDS's splash and onboarding.
//   - Feature list is eNDS's actual v1 Pro benefit set (4 rows) instead of
//     iGBA's 6.
//   - `iNDSPRO` is a WEEKLY plan (iGBA's short-cycle plan is monthly) — the
//     "full price" / "SAVE %" math under the yearly plan annualizes at ×52,
//     not ×12, and detects the short plan via `.contains("week")` instead of
//     an exact `"month"` match.
//   - No "Includes Family Sharing" footer line — not a claim eNDS's
//     StoreKit products (or App Store Connect config) actually make yet.
//   - No `NumberFormatter.localizedCurrencyFormatter()` helper (an iGBA-only
//     extension) — uses a plain inline `NumberFormatter` instead, matching
//     what iGBA's own `calculatePercentageSaved` already does in the same file.
//

import SwiftUI

struct PurchaseView: View {

    @StateObject var purchaseModel: PurchaseModel = PurchaseModel()

    @State private var showCloseButton = false
    @State private var progress: CGFloat = 0.0

    @Binding var isPresented: Bool

    @State private var freeTrial: Bool = true
    /// Set by "See all plans" — reveals the lifetime row for people the
    /// targeting rule wouldn't otherwise show it to (App Review included).
    @State private var showAllPlans = false
    @State private var selectedProductId: String = ""

    // Celebration
    @State private var showCelebration: Bool = false

    // Animated hero
    @State private var heroScale: CGFloat = 0.7
    @State private var heroOpacity: Double = 0.0
    /// Gates the per-row stagger in `featuresSection` — each row keys off
    /// this same flag but carries its own `.delay(index * x)`, same idiom as
    /// `WelcomeView`'s `animatedPages`.
    @State private var featuresRevealed = false
    /// Brief outward pulse on the CTA whenever the selected plan changes —
    /// ties the CTA back to whichever plan/lifetime row was just tapped.
    @State private var ctaPulse = false

    private let allowCloseAfter: CGFloat = 1.0
    var hasCooldown: Bool = true

    private let brandGradient = LinearGradient(
        colors: [Color.indsCrimsonLight, Color.indsCrimsonDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let darkCardBG = Color(UIColor.secondarySystemGroupedBackground)

    let placeholderProductDetails: [PurchaseProductDetails] = [
        PurchaseProductDetails(price: "-", productId: "demo", duration: "week", durationPlanName: NSLocalizedString("Weekly", comment: "Plan name placeholder shown while StoreKit loads"), hasTrial: false),
        PurchaseProductDetails(price: "-", productId: "demo", duration: "year", durationPlanName: NSLocalizedString("Yearly", comment: "Plan name placeholder shown while StoreKit loads"), hasTrial: false)
    ]

    // MARK: - Computed

    var callToActionText: String {
        if let hasTrial = purchaseModel.productDetails.first(where: { $0.productId == selectedProductId })?.hasTrial, hasTrial {
            return NSLocalizedString("Start Free Trial", comment: "")
        }
        return NSLocalizedString("Unlock eNDS PRO", comment: "Purchase CTA button")
    }

    /// A year of the weekly plan, for the "you'd otherwise pay X" comparison.
    /// Built from StoreKit's own `Decimal`, never from re-parsing a formatted
    /// price string: that parse fails in any storefront whose currency format
    /// doesn't match the device locale, and this comparison must not be
    /// guessed at.
    var calculateFullPrice: Double? {
        guard let weekly = purchaseModel.productDetails
            .first(where: { $0.duration.lowercased().contains("week") })?.rawPrice else { return nil }
        return (weekly as NSDecimalNumber).doubleValue * 52
    }

    /// `nil` when the saving can't be computed from real prices — the badge is
    /// then simply not shown. It used to fall back to a hardcoded 24%, which
    /// meant a storefront where the parse failed advertised a discount nobody
    /// had verified; App Review treats an unsubstantiated price claim as
    /// grounds for rejection, and it would be false besides.
    var calculatePercentageSaved: Int? {
        guard let fullPrice = calculateFullPrice, fullPrice > 0,
              let yearly = purchaseModel.productDetails
                .first(where: { $0.duration.lowercased().contains("year") })?.rawPrice else { return nil }
        let saved = Int(100 - (((yearly as NSDecimalNumber).doubleValue / fullPrice) * 100))
        return saved > 0 ? saved : nil
    }

    /// The billing period as a word to show the user. `PurchaseProductDetails
    /// .duration` deliberately stays an English token because the plan-card
    /// logic compares against it (`== "lifetime"`, `.contains("year")`), so it
    /// must be mapped at the point of display — otherwise the 3.1.2(a)
    /// disclosure reads "Facturado 4,99 € por year" in the eight non-English
    /// locales, which is precisely the line that exists to satisfy a legal
    /// requirement.
    private func localizedDuration(_ token: String) -> String {
        switch token {
        case "day":      return NSLocalizedString("day", comment: "Billing period, as in 'billed X per day'")
        case "week":     return NSLocalizedString("week", comment: "Billing period, as in 'billed X per week'")
        case "month":    return NSLocalizedString("month", comment: "Billing period, as in 'billed X per month'")
        case "year":     return NSLocalizedString("year", comment: "Billing period, as in 'billed X per year'")
        case "lifetime": return NSLocalizedString("lifetime", comment: "One-time purchase, not a period")
        default:         return token
        }
    }

    var selectedProduct: PurchaseProductDetails? {
        purchaseModel.productDetails.first(where: { $0.productId == selectedProductId })
    }

    /// Lifetime shows for former subscribers and long-time non-subscribers —
    /// the people for whom a pay-once option is genuinely the better fit.
    var shouldOfferLifetime: Bool {
        purchaseModel.wasFormerSubscriber ||
        UserDefaults.standard.integer(forKey: "eNDSPaywallImpressionCount") >= 40
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            closeButton
                .zIndex(10)

            if showCelebration {
                celebrationOverlay
                    .zIndex(20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, 50)

                        featuresSection
                            .padding(.top, 28)

                        planSelector
                            .padding(.top, 28)

                        ctaButton
                            .padding(.top, 24)

                        footerSection
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .onAppear(perform: onAppearActions)
        .onChange(of: purchaseModel.purchaseSuccess) { _, success in
            if success {
                INDSHaptics.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showCelebration = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isPresented = false
                }
            }
        }
        .onChange(of: purchaseModel.isSubscribed) { _, isSubscribed in
            if isSubscribed && !purchaseModel.purchaseSuccess {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Celebration

    private var celebrationOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(brandGradient)

            Text(NSLocalizedString("Welcome to eNDS PRO!", comment: "Purchase success title"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(brandGradient)

            Text(NSLocalizedString("Thank you for your support!\nEnjoy the full experience.", comment: "Purchase success message"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.indsCrimsonLight.opacity(0.25), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -80, y: -200)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.indsCrimsonDark.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 350, height: 350)
                .offset(x: 120, y: -50)
                .blur(radius: 60)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(brandGradient, lineWidth: 3)
                    .frame(width: 110, height: 110)
                    .opacity(0.5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indsCrimsonLight.opacity(0.15), Color.indsCrimsonDark.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(brandGradient)
            }
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            VStack(spacing: 6) {
                Text("eNDS PRO")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(brandGradient)

                Text(NSLocalizedString("The ultimate DS experience", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // The 48 h courtesy window unlocks every PRO gate silently;
                // without this line it also ENDS silently, which reads as
                // "the update took my features away" in launch-week reviews.
                if let hoursLeft = INDSHoneymoon.remainingHours {
                    Text(String(format: NSLocalizedString("Everything PRO is free during your first 48 hours — about %d h left.", comment: "Honeymoon notice on the paywall; %d is the number of hours remaining"), hoursLeft))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(Color.indsCrimsonLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                if purchaseModel.wasFormerSubscriber {
                    Text(NSLocalizedString("We miss you! Your subscription expired.\nCome back and unlock everything again.", comment: "Win-back message"))
                        .font(.caption)
                        .foregroundColor(Color.indsCrimsonLight.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.horizontal, 12)
                } else {
                    Text(NSLocalizedString("Built with care by an independent developer.\nYour support keeps eNDS moving forward.", comment: "Paywall personal message"))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.horizontal, 12)
                }
            }
            .opacity(heroOpacity)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            featureRow(icon: "infinity", iconColor: .red,
                       title: NSLocalizedString("Everything, forever", comment: ""),
                       subtitle: NSLocalizedString("Every current and future PRO feature", comment: ""),
                       index: 0)
            Divider().padding(.leading, 52)
            featureRow(icon: "camera.filters", iconColor: .orange,
                       title: NSLocalizedString("Display filters", comment: ""),
                       subtitle: NSLocalizedString("Scanlines, for the CRT look", comment: ""),
                       index: 1)
            Divider().padding(.leading, 52)
            featureRow(icon: "square.stack.3d.up.fill", iconColor: .blue,
                       title: NSLocalizedString("All save-state slots", comment: ""),
                       subtitle: NSLocalizedString("Slot 1 + auto-save are free — PRO unlocks slots 2-4", comment: ""),
                       index: 2)
            Divider().padding(.leading, 52)
            featureRow(icon: "photo.on.rectangle.angled", iconColor: .green,
                       title: NSLocalizedString("Custom backgrounds", comment: ""),
                       subtitle: NSLocalizedString("Your own photo behind the game, portrait and landscape", comment: ""),
                       index: 3)
            Divider().padding(.leading, 52)
            featureRow(icon: "heart.fill", iconColor: .pink,
                       title: NSLocalizedString("Support development", comment: ""),
                       subtitle: NSLocalizedString("Keep eNDS independent", comment: ""),
                       index: 4)
        }
        .padding(.vertical, 12)
        .background(darkCardBG)
        .cornerRadius(16)
    }

    /// `index` staggers this row's entrance — see `featuresRevealed`.
    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String, index: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green.opacity(0.8))
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(featuresRevealed ? 1 : 0)
        .offset(y: featuresRevealed ? 0 : 12)
        .motionAnimation(INDSMotion.gentle.delay(0.3 + Double(index) * 0.07), value: featuresRevealed)
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 12) {
            let productDetails = purchaseModel.isFetchingProducts ? placeholderProductDetails : purchaseModel.productDetails

            // Subscriptions only — the lifetime unlock renders as a separate,
            // deliberately understated row below.
            let subscriptions = productDetails.filter { $0.duration != "lifetime" }

            // Show yearly first (best value)
            let sorted = subscriptions.sorted { a, _ in a.duration.lowercased().contains("year") }

            ForEach(sorted) { product in
                planCard(product: product)
            }

            if let lifetime = productDetails.first(where: { $0.duration == "lifetime" }),
               shouldOfferLifetime || showAllPlans {
                lifetimeRow(product: lifetime)
            } else if !shouldOfferLifetime,
                      productDetails.contains(where: { $0.duration == "lifetime" }) {
                // The targeting rule keeps lifetime out of most people's way on
                // purpose, but an IAP submitted with the binary that a reviewer
                // cannot reach at all is a guaranteed 2.1 "Information Needed".
                // One quiet line keeps the funnel and makes it reachable.
                Button {
                    withMotion(.easeInOut(duration: 0.2)) { showAllPlans = true }
                } label: {
                    Text(NSLocalizedString("See all plans", comment: "Reveals the one-time purchase option"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .opacity(purchaseModel.isFetchingProducts ? 0 : 1)
        .allowsHitTesting(!purchaseModel.isFetchingProducts)
        .overlay {
            if purchaseModel.isFetchingProducts {
                ProgressView()
                    .scaleEffect(1.2)
            } else if purchaseModel.productDetails.isEmpty {
                // Never leave a spinner forever: StoreKit returns an empty set
                // whenever the products aren't approved yet, the device is
                // offline, or the sandbox account is wrong — and a paywall that
                // spins for eternity is exactly what a reviewer will screenshot.
                unavailableProductsState
            }
        }
    }

    /// Shown in place of the plan cards when StoreKit gave us nothing.
    private var unavailableProductsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(NSLocalizedString("Plans couldn't be loaded", comment: "Paywall: StoreKit returned no products"))
                .font(.subheadline.weight(.semibold))
            Text(NSLocalizedString("Check your connection and try again. You can keep playing in the meantime — nothing is locked behind this screen except the PRO extras.", comment: "Paywall: no products explanation"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(NSLocalizedString("Try Again", comment: "Retry loading paywall products")) {
                purchaseModel.reloadProducts()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
    }

    private func planCard(product: PurchaseProductDetails) -> some View {
        let isSelected = selectedProductId == product.productId
        let isYearly = product.duration.lowercased().contains("year")

        return Button {
            withMotion(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedProductId = product.productId
            }
            freeTrial = product.hasTrial
            pulseCTA()
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.indsCrimsonLight : Color.gray.opacity(0.3), lineWidth: 2.5)
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Circle()
                                .fill(brandGradient)
                                .frame(width: 14, height: 14)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(product.durationPlanName)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.primary)

                            if isYearly, let saved = calculatePercentageSaved {
                                Text(String(format: NSLocalizedString("SAVE %d%%", comment: "Savings badge"), saved))
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(brandGradient)
                                    .cornerRadius(4)
                            }
                        }

                        if product.hasTrial {
                            Text(String(format: NSLocalizedString("Free trial, then %@ / %@", comment: ""), product.price, localizedDuration(product.duration)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            // No strikethrough anchor price here on purpose:
                            // "was $103.48" next to a yearly plan is the
                            // inflated-reference pattern hostile readers
                            // screenshot. The SAVE badge already carries the
                            // (real, StoreKit-derived) comparison.
                            Text("\(product.price) / \(localizedDuration(product.duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if isYearly, let saved = calculatePercentageSaved {
                        Text(String(format: NSLocalizedString("-%d%%", comment: ""), saved))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(Color.indsCrimsonLight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.indsCrimsonLight.opacity(0.08) : darkCardBG)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? brandGradient : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: isSelected ? 2 : 1)
                )
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    // MARK: - Lifetime option (deliberately understated)

    private func lifetimeRow(product: PurchaseProductDetails) -> some View {
        let isSelected = selectedProductId == product.productId
        return Button {
            withMotion(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedProductId = product.productId
                freeTrial = false
            }
            pulseCTA()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "infinity.circle.fill" : "infinity.circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.indsCrimsonLight : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Prefer to pay once?", comment: "Lifetime option title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(String(format: NSLocalizedString("Lifetime — %@. No subscription, ever.", comment: "Lifetime option subtitle with price"), product.price))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.indsCrimsonLight)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.indsCrimsonLight : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        VStack(spacing: 14) {
            ZStack {
                ProgressView()
                    .tint(.white)
                    .opacity(purchaseModel.isPurchasing ? 1 : 0)

                Button {
                    if !purchaseModel.isPurchasing {
                        purchaseModel.purchaseSubscription(productId: selectedProductId)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Text(callToActionText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .background(brandGradient)
                    .cornerRadius(14)
                    .shadow(color: Color.indsCrimsonDark.opacity(0.35), radius: 12, x: 0, y: 6)
                }
                .opacity(purchaseModel.isPurchasing ? 0 : 1)
            }
            // Brief pulse whenever a plan/lifetime row is tapped — see
            // `pulseCTA()`.
            .scaleEffect(ctaPulse ? 1.035 : 1.0)
            .opacity(purchaseModel.isFetchingProducts ? 0 : 1)

            // Auto-renewal / cancel-anytime disclosure, per plan.
            if let product = selectedProduct {
                if product.duration == "lifetime" {
                    Text(String(format: NSLocalizedString("One-time payment of %@ — yours forever.", comment: "Lifetime pricing breakdown"), product.price))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if product.hasTrial {
                    Text(String(format: NSLocalizedString("Free trial, then %@ / %@. Renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account settings.", comment: "Auto-renewal disclosure with trial, required by App Review guideline 3.1.2"), product.price, localizedDuration(product.duration)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(String(format: NSLocalizedString("Billed %@ per %@. Renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account settings.", comment: "Auto-renewal disclosure required by App Review guideline 3.1.2"), product.price, localizedDuration(product.duration)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 10) {
            Button(action: {
                purchaseModel.restorePurchases()
            }) {
                HStack(spacing: 6) {
                    if purchaseModel.isRestoring {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(purchaseModel.isRestoring
                         ? NSLocalizedString("Restoring…", comment: "")
                         : NSLocalizedString("Restore Purchases", comment: ""))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .disabled(purchaseModel.isSubscribed || purchaseModel.isRestoring)
            .alert(item: Binding<PurchaseErrorWrapper?>(
                get: { purchaseModel.purchaseError.map { PurchaseErrorWrapper(message: $0) } },
                set: { _ in purchaseModel.purchaseError = nil }
            )) { wrapper in
                Alert(
                    title: Text(NSLocalizedString("Notice", comment: "")),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(NSLocalizedString("Purchases Restored", comment: "Restore success title"), isPresented: $purchaseModel.restoreSuccess) {
                Button("OK") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isPresented = false
                    }
                }
            } message: {
                Text(NSLocalizedString("eNDS PRO has been restored. Enjoy!", comment: "Restore success message"))
            }

            // Legal links — same support site as iGBA (one hub for the
            // family of apps).
            HStack(spacing: 14) {
                Button(NSLocalizedString("Terms of Use", comment: "")) {
                    UIApplication.shared.open(INDSConstants.termsURL)
                }

                Text("·").foregroundColor(.secondary)

                Button(NSLocalizedString("Privacy Policy", comment: "")) {
                    UIApplication.shared.open(INDSConstants.privacyPolicyURL)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()
            if hasCooldown && !showCloseButton {
                Circle()
                    .trim(from: 0.0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundColor(.secondary.opacity(0.3))
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 20)
    }

    // MARK: - Actions

    private func onAppearActions() {
        if purchaseModel.isSubscribed {
            isPresented = false
            return
        }

        // Impression counter feeds the lifetime-visibility rule.
        let impressions = UserDefaults.standard.integer(forKey: "eNDSPaywallImpressionCount") + 1
        UserDefaults.standard.set(impressions, forKey: "eNDSPaywallImpressionCount")

        // Default to yearly (best value) — NEVER the lifetime.
        selectedProductId = "iNDSPROYearly"

        withMotion(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }
        // Each row carries its own delay (see `featureRow`) — this just
        // flips the shared trigger.
        withMotion { featuresRevealed = true }

        // Close-button cooldown ring: a real countdown, not decorative
        // motion — left as plain `withAnimation` (not `withMotion`) so it
        // still visibly fills over `allowCloseAfter` seconds under Reduce
        // Motion instead of snapping straight to "closable" with no cue why.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: allowCloseAfter)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + allowCloseAfter) {
                withAnimation { showCloseButton = true }
            }
        }
    }

    /// Ties the CTA back to whichever plan/lifetime row was just tapped — a
    /// brief outward-then-settle pulse, since the price/wording above it
    /// changes with the selection and shouldn't do so with zero
    /// acknowledgement. Unlike the plan/lifetime rows' own press feedback,
    /// this reacts on a *different* element than the one tapped, so — via
    /// `withMotion` — it collapses to a quick fade under Reduce Motion
    /// instead of always scaling.
    private func pulseCTA() {
        withMotion(INDSMotion.snappy) { ctaPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withMotion(INDSMotion.snappy) { ctaPulse = false }
        }
    }

    // MARK: - Helpers

    func toLocalCurrencyString(_ value: Double) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: value))
    }
}

private struct PurchaseErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    PurchaseView(isPresented: .constant(true))
}
