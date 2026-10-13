import SwiftUI

/// Short faded curve under the compact source bubble in a collapsed reply.
struct ReplyThreadCurve: Shape {
    let sourceDirection: ChatMessage.Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if sourceDirection == .incoming {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.minX + 5, y: rect.maxY * 0.78),
                control2: CGPoint(x: rect.midX, y: rect.maxY)
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - 5, y: rect.maxY * 0.78),
                control2: CGPoint(x: rect.midX, y: rect.maxY)
            )
        }
        return path
    }
}

/// Bracket displayed beside a source message and several replies in focus mode.
struct ReplyThreadBracket: Shape {
    let opensToTrailing: Bool

    func path(in rect: CGRect) -> Path {
        let edgeX = opensToTrailing ? rect.maxX : rect.minX
        let spineX = opensToTrailing ? rect.minX : rect.maxX
        let radius = min(26, rect.width)
        var path = Path()

        path.move(to: CGPoint(x: edgeX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: spineX, y: rect.minY + radius),
            control1: CGPoint(x: spineX, y: rect.minY),
            control2: CGPoint(x: spineX, y: rect.minY + radius * 0.45)
        )
        path.addLine(to: CGPoint(x: spineX, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: edgeX, y: rect.maxY),
            control1: CGPoint(x: spineX, y: rect.maxY - radius * 0.45),
            control2: CGPoint(x: spineX, y: rect.maxY)
        )
        return path
    }
}

#Preview("Кривая ответа") {
    VStack(spacing: 24) {
        ReplyThreadCurve(sourceDirection: .incoming)
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: 90, height: 26)
        ReplyThreadCurve(sourceDirection: .outgoing)
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: 90, height: 26)
    }
    .padding()
}

#Preview("Скобка ветки") {
    HStack(spacing: 40) {
        ReplyThreadBracket(opensToTrailing: true)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 38, height: 260)
        ReplyThreadBracket(opensToTrailing: false)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 38, height: 260)
    }
    .padding()
}
