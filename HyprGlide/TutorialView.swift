//
//  TutorialView.swift
//  HyprGlide
//
//  Walkthrough shown on first launch and available from Settings.
//

import SwiftUI

struct TutorialView: View {
    let colorTheme: ColorTheme
    var primaryActionTitle: String = "Let's Glide"
    var onDismiss: (() -> Void)?
    
    private let powerUpLineWidth: CGFloat = 5.5
    
    private var accentColor: Color {
        colorTheme.primaryColor
    }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.05, green: 0.05, blue: 0.1)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                ScrollView {
                    VStack(spacing: 18) {
                        tutorialCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Objective")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Stay alive by dodging falling objects. Score ticks up over time and near-misses earn bonus points.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        tutorialCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Controls")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                controlRow(title: "Tilt", detail: "Lean your device left/right to steer. Toggle Tilt and adjust sensitivity in Settings.")
                                
                                Divider().background(Color.white.opacity(0.15))
                                
                                controlRow(title: "Drag", detail: "Touch and drag anywhere to move the orb directly. Drag overrides tilt while your finger is down.")
                            }
                        }
                        
                        tutorialCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Power-Ups")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                powerUpRow(icon: AnyView(Circle().strokeBorder(powerUpColor(colorTheme.powerUpColor.ring), lineWidth: powerUpLineWidth)),
                                           title: "Slow Motion",
                                           description: "Slows down opponents in multiplayer.",
                                           color: powerUpColor(colorTheme.powerUpColor.ring))
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                powerUpRow(icon: AnyView(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(powerUpColor(colorTheme.invincibilityColor.ring), lineWidth: powerUpLineWidth)),
                                           title: "Invincibility",
                                           description: nil,
                                           color: powerUpColor(colorTheme.invincibilityColor.ring))
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                powerUpRow(icon: AnyView(Triangle()
                                    .stroke(powerUpColor(colorTheme.attackModeColor.ring),
                                            style: StrokeStyle(lineWidth: powerUpLineWidth, lineCap: .round, lineJoin: .round))),
                                           title: "Attack Mode",
                                           description: "Smash the falling objects for bonus points.",
                                           color: powerUpColor(colorTheme.attackModeColor.ring))
                            }
                        }
                        
                        Text("You can reopen this guide anytime from Settings.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
                
                Button {
                    onDismiss?()
                } label: {
                    Text(primaryActionTitle.uppercased())
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .strokeBorder(accentColor, lineWidth: 2.5)
                        )
                }
                .padding(.bottom, 24)
                .padding(.top, 12)
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 6) {
            Text("How to Play")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.top, 32)
        .padding(.bottom, 22)
    }
    
    @ViewBuilder
    private func tutorialCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
    
    private func controlRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.9))
                .frame(width: 12, height: 12)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
    
    private func powerUpRow(icon: AnyView,
                            title: String,
                            description: String?,
                            color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .frame(width: 34, height: 34)
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                if let description {
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func powerUpColor(_ components: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(red: Double(components.0),
              green: Double(components.1),
              blue: Double(components.2))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        path.move(to: top)
        path.addLine(to: bottomLeft)
        path.addLine(to: bottomRight)
        path.closeSubpath()
        return path
    }
}

#Preview {
    TutorialView(colorTheme: .neonBlue)
}
