import Foundation

/// Provides mock MultiplayerSnapshot data for UI testing and bootstrap validation.
struct MockMultiplayerPayloads {
    
    static func generateInitialDealSnapshot(localPlayerId: String, opponentId: String) -> MultiplayerSnapshot {
        let matchState = generateMatchSnapshot(localPlayerId: localPlayerId, opponentId: opponentId, phase: .inTurn)
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 1,
            lastIncludedEventId: nil,
            state: matchState
        )
    }
    
    static func generateOpponentTurnSnapshot(localPlayerId: String, opponentId: String) -> MultiplayerSnapshot {
        let matchState = generateMatchSnapshot(localPlayerId: localPlayerId, opponentId: opponentId, phase: .inTurn, currentPlayerId: opponentId)
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 2,
            lastIncludedEventId: nil,
            state: matchState
        )
    }
    
    static func generateMatchEndSnapshot(localPlayerId: String, opponentId: String, winnerId: String) -> MultiplayerSnapshot {
        let scoreboard = MultiplayerScoreboard(
            roundIndex: 0,
            playerScores: [
                MultiplayerPlayerScore(playerId: localPlayerId, score: (winnerId == localPlayerId ? 7 : 0), goCount: (winnerId == localPlayerId ? 1 : 0), money: 10000),
                MultiplayerPlayerScore(playerId: opponentId, score: (winnerId == opponentId ? 7 : 0), goCount: (winnerId == opponentId ? 1 : 0), money: 10000)
            ],
            winnerPlayerId: winnerId
        )
        
        let matchState = generateMatchSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            phase: .matchEnded,
            scoreboard: scoreboard
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 10,
            lastIncludedEventId: nil,
            state: matchState
        )
    }
    
    static func generateSpecialEventSnapshot(localPlayerId: String, opponentId: String, effect: String) -> MultiplayerSnapshot {
        let matchState = generateMatchSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            phase: .inTurn,
            lastActionEffect: effect
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 50,
            lastIncludedEventId: nil,
            state: matchState
        )
    }

    static func generateReconnectingSnapshot(localPlayerId: String, opponentId: String, secondsRemaining: Int) -> MultiplayerSnapshot {
        let deadline = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(secondsRemaining)))
        let resume = MultiplayerResumeState(isResumable: true, graceDeadlineAt: deadline)
        
        // Generate a standard match state but with resume info
        let matchState = generateMatchSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            phase: .inTurn,
            currentPlayerId: opponentId, // Usually happens on opponent's turn
            scoreboard: nil
        )
        
        // Inject the resume state (since generateMatchSnapshot currently defaults to empty resume)
        // Note: we might want to update generateMatchSnapshot to accept resume, but for now we manually wrap it if needed
        // Actually, MultiplayerMatchSnapshot is a struct and generateMatchSnapshot returns it.
        // Let's modify generateMatchSnapshot to accept resume state.
        
        let matchStateWithResume = MultiplayerMatchSnapshot(
            traceId: matchState.traceId,
            roomId: matchState.roomId,
            gameId: matchState.gameId,
            viewerPlayerId: matchState.viewerPlayerId,
            engineVersion: matchState.engineVersion,
            ruleConfigVersion: matchState.ruleConfigVersion,
            stateVersion: matchState.stateVersion,
            lastEventId: matchState.lastEventId,
            phase: matchState.phase,
            turnId: matchState.turnId,
            currentPlayerId: matchState.currentPlayerId,
            dealerPlayerId: matchState.dealerPlayerId,
            starterPlayerId: matchState.starterPlayerId,
            players: matchState.players,
            table: matchState.table,
            deck: matchState.deck,
            pendingChoice: matchState.pendingChoice,
            scoreboard: matchState.scoreboard,
            timers: matchState.timers,
            resume: resume,
            lastActionEffect: matchState.lastActionEffect
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 100,
            lastIncludedEventId: nil,
            state: matchStateWithResume
        )
    }

    static func generateChatSnapshot(localPlayerId: String, opponentId: String, playerId: String, emojiId: String) -> MultiplayerSnapshot {
        let chat = MultiplayerChatPresence(
            playerId: playerId,
            emojiId: emojiId,
            text: nil,
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
        
        // Generate a standard match state but with the chat info
        let matchState = generateMatchSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            phase: .inTurn,
            currentPlayerId: localPlayerId, // Arbitrary
            scoreboard: nil
        )
        
        let matchStateWithChat = MultiplayerMatchSnapshot(
            traceId: matchState.traceId,
            roomId: matchState.roomId,
            gameId: matchState.gameId,
            viewerPlayerId: matchState.viewerPlayerId,
            engineVersion: matchState.engineVersion,
            ruleConfigVersion: matchState.ruleConfigVersion,
            stateVersion: matchState.stateVersion + 1,
            lastEventId: matchState.lastEventId,
            phase: matchState.phase,
            turnId: matchState.turnId,
            currentPlayerId: matchState.currentPlayerId,
            dealerPlayerId: matchState.dealerPlayerId,
            starterPlayerId: matchState.starterPlayerId,
            players: matchState.players,
            table: matchState.table,
            deck: matchState.deck,
            pendingChoice: matchState.pendingChoice,
            scoreboard: matchState.scoreboard,
            timers: matchState.timers,
            resume: matchState.resume,
            lastActionEffect: matchState.lastActionEffect,
            lastChat: chat
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .localPreview,
            scope: .player,
            snapshotStateVersion: 200,
            lastIncludedEventId: nil,
            state: matchStateWithChat
        )
    }

    static func generateScoreboardSnapshot(localPlayerId: String, opponentId: String, localScore: Int, opponentScore: Int, roundIndex: Int) -> MultiplayerSnapshot {
        let scoreboard = MultiplayerScoreboard(
            roundIndex: roundIndex,
            playerScores: [
                MultiplayerPlayerScore(playerId: localPlayerId, score: localScore, goCount: localScore > 7 ? 1 : 0, money: 10000 + localScore * 100),
                MultiplayerPlayerScore(playerId: opponentId, score: opponentScore, goCount: 0, money: 10000 - localScore * 100)
            ],
            winnerPlayerId: localScore > opponentScore ? localPlayerId : (opponentScore > localScore ? opponentId : nil)
        )
        
        let matchState = generateMatchSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            phase: .roundEnded,
            currentPlayerId: localPlayerId,
            scoreboard: scoreboard
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .resync,
            scope: .player,
            snapshotStateVersion: 300,
            lastIncludedEventId: nil,
            state: matchState
        )
    }

    static func generateMatchEndSnapshot(winnerId: String, reason: MultiplayerMatchEndReason) -> MultiplayerSnapshot {
        let scoreboard = MultiplayerScoreboard(
            roundIndex: 3,
            playerScores: [
                MultiplayerPlayerScore(playerId: "p1", score: 20, goCount: 2, money: 12000),
                MultiplayerPlayerScore(playerId: "p2", score: 0, goCount: 0, money: 8000)
            ],
            winnerPlayerId: winnerId
        )
        
        // In matchEnded, we use the phase string explicitly
        let matchState = generateMatchSnapshot(
            localPlayerId: "p1",
            opponentId: "p2",
            phase: .matchEnded, // GameState.ended maps to "roundEnded" or "matchEnded"
            currentPlayerId: winnerId,
            scoreboard: scoreboard
        )
        
        return MultiplayerSnapshot(
            snapshotId: UUID().uuidString,
            reason: .resync,
            scope: .player,
            snapshotStateVersion: 400,
            lastIncludedEventId: nil,
            state: matchState
        )
    }
    
    // Internal helper to reduce boilerplate
    private static func generateMatchSnapshot(
        localPlayerId: String,
        opponentId: String,
        phase: MultiplayerPhase,
        currentPlayerId: String? = nil,
        scoreboard: MultiplayerScoreboard? = nil,
        lastActionEffect: String? = nil
    ) -> MultiplayerMatchSnapshot {
        
        // 10 Cards for Local Player
        let localHand = (1...10).map { i in
            MultiplayerCardSummary(
                cardId: "local_c\(i)",
                month: (i % 12) + 1,
                kind: "junk",
                imageIndex: 0,
                selectedRole: nil
            )
        }
        
        // 8 Cards for Table
        let tableCards = (1...8).map { i in
            MultiplayerCardSummary(
                cardId: "table_c\(i)",
                month: ((i + 5) % 12) + 1,
                kind: "junk",
                imageIndex: 0,
                selectedRole: nil
            )
        }
        
        let localPlayer = MultiplayerPlayerProjection(
            playerId: localPlayerId,
            seatIndex: 0,
            name: "Me",
            hand: localHand,
            handCount: 10,
            captured: MultiplayerCapturedCards(bright: [], animal: [], ribbon: [], junk: []),
            score: 0,
            money: 10000,
            goCount: 0,
            shakeCount: 0,
            isConnected: true,
            isReady: true,
            presenceSource: .localPreview,
            isViewer: false
        )
        
        let opponentPlayer = MultiplayerPlayerProjection(
            playerId: opponentId,
            seatIndex: 1,
            name: "Opponent",
            hand: nil, // Hidden
            handCount: 10,
            captured: MultiplayerCapturedCards(bright: [], animal: [], ribbon: [], junk: []),
            score: 0,
            money: 10000,
            goCount: 0,
            shakeCount: 0,
            isConnected: true,
            isReady: true,
            presenceSource: .localPreview,
            isViewer: false
        )
        
        return MultiplayerMatchSnapshot(
            traceId: nil,
            roomId: "room_1",
            gameId: "game_1",
            viewerPlayerId: localPlayerId,
            engineVersion: "1.0",
            ruleConfigVersion: "1.0",
            stateVersion: 1,
            lastEventId: nil,
            phase: phase,
            turnId: "turn_1",
            currentPlayerId: currentPlayerId ?? localPlayerId,
            dealerPlayerId: localPlayerId,
            starterPlayerId: localPlayerId,
            players: [localPlayer, opponentPlayer],
            table: MultiplayerTableSnapshot(cards: tableCards, monthBuckets: [:]),
            deck: MultiplayerDeckSnapshot(remainingCount: 20),
            pendingChoice: nil,
            scoreboard: scoreboard ?? MultiplayerScoreboard(roundIndex: 0, playerScores: [], winnerPlayerId: nil),
            timers: MultiplayerTimers(turnDeadlineAt: nil, choiceDeadlineAt: nil),
            resume: MultiplayerResumeState(isResumable: false, graceDeadlineAt: nil),
            lastActionEffect: lastActionEffect
        )
    }
}
