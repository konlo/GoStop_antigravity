import SwiftUI

struct SpecialEventPopup: Identifiable {
    enum Kind {
        case sweep
        case ttadak
        case jjok
        case cheongdan
        case hongdan
        case godori
        case gusa
        case seolsa
        case seolsaEat
        case selfSeolsaEat
        case tripleSeolsaEnd
        case shake
        case bomb

        var accentColor: Color {
            switch self {
            case .sweep:
                return .yellow
            case .ttadak:
                return .orange
            case .jjok:
                return .indigo
            case .cheongdan:
                return .blue
            case .hongdan:
                return .red
            case .godori:
                return .green
            case .gusa:
                return .teal
            case .seolsa:
                return .pink
            case .seolsaEat:
                return .orange
            case .selfSeolsaEat:
                return .red
            case .tripleSeolsaEnd:
                return .mint
            case .shake:
                return .cyan
            case .bomb:
                return .purple
            }
        }

        var iconName: String {
            switch self {
            case .sweep:
                return "wind"
            case .ttadak:
                return "sparkle.magnifyingglass"
            case .jjok:
                return "sparkles"
            case .cheongdan:
                return "tag.fill"
            case .hongdan:
                return "tag.circle.fill"
            case .godori:
                return "bird.fill"
            case .gusa:
                return "9.circle.fill"
            case .seolsa:
                return "exclamationmark.triangle.fill"
            case .seolsaEat:
                return "hand.thumbsup.fill"
            case .selfSeolsaEat:
                return "flame.fill"
            case .tripleSeolsaEnd:
                return "trophy.fill"
            case .shake:
                return "waveform.path.ecg"
            case .bomb:
                return "burst.fill"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}

struct SpecialEventPopupTiming {
    let displayDuration: TimeInterval
    let dismissDuration: TimeInterval
    let queueAdvanceDelay: TimeInterval

    static let `default` = SpecialEventPopupTiming(
        displayDuration: 1.7,
        dismissDuration: 0.18,
        queueAdvanceDelay: 0.12
    )
}

private struct SpecialEventPopupLogDefinition {
    let logMarker: String
    let actorMarker: String
    let buildPopup: (String) -> SpecialEventPopup
}

enum SpecialEventPopupMapper {
    private static let definitions: [SpecialEventPopupLogDefinition] = [
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.triple_seolsa"),
            actorMarker: gameText("log.actor_marker.triple_seolsa"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .tripleSeolsaEnd,
                    title: gameText("special_popup.title.triple_seolsa"),
                    detail: gameText("special_popup.detail.triple_seolsa", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.shake"),
            actorMarker: gameText("log.actor_marker.shake"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .shake,
                    title: gameText("special_popup.title.shake"),
                    detail: gameText("special_popup.detail.shake", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.bomb"),
            actorMarker: gameText("log.actor_marker.bomb"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .bomb,
                    title: gameText("special_popup.title.bomb"),
                    detail: gameText("special_popup.detail.bomb", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.sweep"),
            actorMarker: gameText("log.actor_marker.sweep"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .sweep,
                    title: gameText("special_popup.title.sweep"),
                    detail: gameText("special_popup.detail.sweep", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.ttadak"),
            actorMarker: gameText("log.actor_marker.ttadak"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .ttadak,
                    title: gameText("special_popup.title.ttadak"),
                    detail: gameText("special_popup.detail.ttadak", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.jjok"),
            actorMarker: gameText("log.actor_marker.jjok"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .jjok,
                    title: gameText("special_popup.title.jjok"),
                    detail: gameText("special_popup.detail.jjok", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.cheongdan"),
            actorMarker: gameText("log.actor_marker.cheongdan"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .cheongdan,
                    title: gameText("special_popup.title.cheongdan"),
                    detail: gameText("special_popup.detail.cheongdan", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.hongdan"),
            actorMarker: gameText("log.actor_marker.hongdan"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .hongdan,
                    title: gameText("special_popup.title.hongdan"),
                    detail: gameText("special_popup.detail.hongdan", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.godori"),
            actorMarker: gameText("log.actor_marker.godori"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .godori,
                    title: gameText("special_popup.title.godori"),
                    detail: gameText("special_popup.detail.godori", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.gusa"),
            actorMarker: gameText("log.actor_marker.gusa"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .gusa,
                    title: gameText("special_popup.title.gusa"),
                    detail: gameText("special_popup.detail.gusa", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.seolsa"),
            actorMarker: gameText("log.actor_marker.seolsa"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .seolsa,
                    title: gameText("special_popup.title.seolsa"),
                    detail: gameText("special_popup.detail.seolsa", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.seolsa_eat"),
            actorMarker: gameText("log.actor_marker.seolsa_eat"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .seolsaEat,
                    title: gameText("special_popup.title.seolsa_eat"),
                    detail: gameText("special_popup.detail.seolsa_eat", ["player": actor])
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: gameText("log.marker.self_seolsa_eat"),
            actorMarker: gameText("log.actor_marker.self_seolsa_eat"),
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .selfSeolsaEat,
                    title: gameText("special_popup.title.self_seolsa_eat"),
                    detail: gameText("special_popup.detail.self_seolsa_eat", ["player": actor])
                )
            }
        ),
    ]

    static func popup(from log: String) -> SpecialEventPopup? {
        for definition in definitions where log.contains(definition.logMarker) {
            let actor = actorName(in: log, marker: definition.actorMarker) ?? gameText("players.default.anonymous")
            return definition.buildPopup(actor)
        }
        return nil
    }

    private static func actorName(in log: String, marker: String) -> String? {
        guard let markerRange = log.range(of: marker) else { return nil }
        let actor = log[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return actor.isEmpty ? nil : actor
    }
}

@MainActor
final class SpecialEventPopupCoordinator: ObservableObject {
    @Published private(set) var activePopup: SpecialEventPopup? = nil
    @Published private(set) var pendingQueueCount: Int = 0

    private var popupQueue: [SpecialEventPopup] = []
    private var generation: Int = 0
    private var lastProcessedEventLogCount: Int = 0
    private let timing: SpecialEventPopupTiming
    private let popupMapper: (String) -> SpecialEventPopup?

    init(
        timing: SpecialEventPopupTiming = .default,
        popupMapper: @escaping (String) -> SpecialEventPopup? = SpecialEventPopupMapper.popup(from:)
    ) {
        self.timing = timing
        self.popupMapper = popupMapper
    }

    var hasActiveOrPendingPopups: Bool {
        activePopup != nil || !popupQueue.isEmpty
    }

    func markExistingLogsProcessed(_ eventLogs: [String]) {
        lastProcessedEventLogCount = eventLogs.count
    }

    func process(eventLogs: [String]) {
        if eventLogs.count < lastProcessedEventLogCount {
            lastProcessedEventLogCount = eventLogs.count
            reset()
            return
        }
        guard lastProcessedEventLogCount < eventLogs.count else { return }

        let newLogs = Array(eventLogs[lastProcessedEventLogCount..<eventLogs.count])
        lastProcessedEventLogCount = eventLogs.count

        for log in newLogs {
            if let popup = popupMapper(log) {
                enqueue(popup)
            }
        }
    }

    func reset() {
        generation += 1
        activePopup = nil
        popupQueue.removeAll()
        pendingQueueCount = 0
    }

    private func enqueue(_ popup: SpecialEventPopup) {
        if activePopup?.kind == popup.kind && activePopup?.detail == popup.detail {
            return
        }
        if popupQueue.last?.kind == popup.kind && popupQueue.last?.detail == popup.detail {
            return
        }
        popupQueue.append(popup)
        pendingQueueCount = popupQueue.count
        showNextIfNeeded()
    }

    private func showNextIfNeeded() {
        guard activePopup == nil else { return }
        guard !popupQueue.isEmpty else {
            pendingQueueCount = 0
            return
        }

        generation += 1
        let currentGeneration = generation
        let nextPopup = popupQueue.removeFirst()
        pendingQueueCount = popupQueue.count

        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            activePopup = nextPopup
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timing.displayDuration) {
            guard currentGeneration == self.generation else { return }
            withAnimation(.easeOut(duration: self.timing.dismissDuration)) {
                self.activePopup = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.timing.queueAdvanceDelay) {
                guard currentGeneration == self.generation else { return }
                self.showNextIfNeeded()
            }
        }
    }
}

struct SpecialEventPopupView: View {
    let popup: SpecialEventPopup

    var body: some View {
        VStack(spacing: 8) {
            Text(popup.title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(popup.kind.accentColor)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.85), radius: 5, x: 0, y: 2)

            Text(popup.detail)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}
