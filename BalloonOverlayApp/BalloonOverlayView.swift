import SwiftUI

struct BalloonOverlayView: View {
    let settings: OverlaySettings
    let onFinished: () -> Void

    @State private var xRatio = 0.5
    @State private var yPosition: Double?

    var body: some View {
        GeometryReader { proxy in
            let balloonSize = min(max(proxy.size.width * 0.14, 120), 180)
            let travelDistance = proxy.size.height + balloonSize * 2
            let animationDuration = max(travelDistance / settings.climbSpeed, 1.0)
            let balloon = settings.activeBalloon
            let minX = balloonSize * 0.72
            let maxX = max(proxy.size.width - balloonSize * 0.72, minX)
            let startY = proxy.size.height + balloonSize
            let endY = -balloonSize
            let middleY = proxy.size.height / 2

            ZStack {
                balloonView(size: balloonSize, balloon: balloon)
                    .position(
                        x: minX + (maxX - minX) * xRatio,
                        y: yPosition ?? startY
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
            .onAppear {
                xRatio = resolvedXRatio(for: balloon)
                yPosition = startY
                startAnimation(
                    balloon: balloon,
                    startY: startY,
                    middleY: middleY,
                    endY: endY,
                    totalDuration: animationDuration
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func startAnimation(
        balloon: BalloonProfile,
        startY: Double,
        middleY: Double,
        endY: Double,
        totalDuration: Double
    ) {
        guard balloon.pausesAtMiddle else {
            withAnimation(.linear(duration: totalDuration)) {
                yPosition = endY
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.2) {
                onFinished()
            }
            return
        }

        let firstDistance = abs(startY - middleY)
        let secondDistance = abs(middleY - endY)
        let fullDistance = max(firstDistance + secondDistance, 1)
        let firstDuration = max(totalDuration * firstDistance / fullDistance, 0.1)
        let secondDuration = max(totalDuration * secondDistance / fullDistance, 0.1)
        let pauseDuration = min(max(balloon.middlePauseDuration, 0.1), 30)

        withAnimation(.linear(duration: firstDuration)) {
            yPosition = middleY
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + firstDuration + pauseDuration) {
            withAnimation(.linear(duration: secondDuration)) {
                yPosition = endY
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + firstDuration + pauseDuration + secondDuration + 0.2) {
            onFinished()
        }
    }

    private func resolvedXRatio(for balloon: BalloonProfile) -> Double {
        if balloon.positionName == "ランダム" {
            return [0.2, 0.5, 0.8].randomElement() ?? 0.5
        }

        return OverlaySettings.positionOptions.first(where: { $0.name == balloon.positionName })?.ratio ?? 0.5
    }

    private func balloonView(size: Double, balloon: BalloonProfile) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: balloon.colorStartHex),
                                Color(hex: balloon.colorEndHex)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)

                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .offset(x: -size * 0.19, y: -size * 0.18)

                contentView(for: balloon)
                    .frame(width: size * 0.58, height: size * 0.58)
                    .clipShape(Circle())
            }
            .frame(width: size, height: size)

            Triangle()
                .fill(Color(hex: balloon.colorEndHex))
                .frame(width: size * 0.18, height: size * 0.15)
                .offset(y: -size * 0.03)

            Rectangle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 2, height: size * 0.5)
                .offset(y: -size * 0.03)
        }
    }

    @ViewBuilder
    private func contentView(for balloon: BalloonProfile) -> some View {
        if let imageName = balloon.imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
        } else {
            Text(balloon.text)
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.35)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(6)
        }
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
