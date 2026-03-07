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
            logMarker: "reached Triple Seolsa",
            actorMarker: " reached",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .tripleSeolsaEnd,
                    title: "삼뻑 종료",
                    detail: "\(actor)이(가) 3뻑으로 라운드를 종료했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "declared SHAKE for month",
            actorMarker: " declared",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .shake,
                    title: "흔들기",
                    detail: "\(actor)이(가) 흔들기를 선언했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered BOMB!",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .bomb,
                    title: "폭탄",
                    detail: "\(actor)이(가) 폭탄을 사용했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "swept the table (싹쓸이)!",
            actorMarker: " swept",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .sweep,
                    title: "싹쓸이",
                    detail: "\(actor)이(가) 테이블을 싹쓸이했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 따닥(Ttadak)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .ttadak,
                    title: "따닥",
                    detail: "\(actor)이(가) 따닥을 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 쪽(Jjok)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .jjok,
                    title: "쪽",
                    detail: "\(actor)이(가) 쪽을 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 청단(Cheongdan)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .cheongdan,
                    title: "청단",
                    detail: "\(actor)이(가) 청단을 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 홍단(Hongdan)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .hongdan,
                    title: "홍단",
                    detail: "\(actor)이(가) 홍단을 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 고도리(Godori)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .godori,
                    title: "고도리",
                    detail: "\(actor)이(가) 고도리를 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 구사(Gusa)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .gusa,
                    title: "구사",
                    detail: "\(actor)이(가) 구사를 달성했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 뻑(Seolsa)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .seolsa,
                    title: "뻑(설사)",
                    detail: "\(actor)의 뻑(설사) 이벤트가 발생했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 뻑 먹기(Seolsa Eat)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .seolsaEat,
                    title: "뻑 먹기",
                    detail: "\(actor)이(가) 뻑 먹기를 성공했습니다."
                )
            }
        ),
        SpecialEventPopupLogDefinition(
            logMarker: "triggered 자뻑(Self Seolsa Eat)",
            actorMarker: " triggered",
            buildPopup: { actor in
                SpecialEventPopup(
                    kind: .selfSeolsaEat,
                    title: "자뻑",
                    detail: "\(actor)의 자뻑 먹기 이벤트가 발생했습니다."
                )
            }
        ),
    ]

    static func popup(from log: String) -> SpecialEventPopup? {
        for definition in definitions where log.contains(definition.logMarker) {
            let actor = actorName(in: log, marker: definition.actorMarker) ?? "플레이어"
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
