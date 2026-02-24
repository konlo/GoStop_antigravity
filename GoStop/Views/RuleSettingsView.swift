import SwiftUI

struct RuleSettingsView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("게임 규칙 설정 (rule.yaml)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.8))
                
                if let config = configManager.ruleConfig {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsSection(title: "점수 계산 (Scoring)", content: scoringSettings(config: config))
                            settingsSection(title: "패널티 (Penalties)", content: penaltySettings(config: config))
                            settingsSection(title: "특수 동작 (Special Moves)", content: specialMoveSettings(config: config))
                            settingsSection(title: "게임 종료 (Endgame)", content: endgameSettings(config: config))
                        }
                        .padding()
                    }
                } else {
                    Text("설정을 불러올 수 없습니다.")
                        .foregroundColor(.white)
                        .padding()
                }
                
                // Save/Close Button
                Button(action: { isPresented = false }) {
                    Text("확인")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .frame(maxWidth: 500, maxHeight: 700)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 20)
            .padding(20)
        }
    }
    
    private func settingsSection<Content: View>(title: String, content: Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.blue.opacity(0.8))
                .padding(.bottom, 5)
            
            content
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
        }
    }
    
    @ViewBuilder
    private func scoringSettings(config: RuleConfig) -> some View {
        VStack(spacing: 12) {
            settingStepper(label: "삼광 점수", value: Binding(get: { configManager.ruleConfig?.scoring.kwang.samgwang ?? 0 }, set: { configManager.ruleConfig?.scoring.kwang.samgwang = $0 }))
            settingStepper(label: "비삼광 점수", value: Binding(get: { configManager.ruleConfig?.scoring.kwang.bisamgwang ?? 0 }, set: { configManager.ruleConfig?.scoring.kwang.bisamgwang = $0 }))
            settingStepper(label: "사광 점수", value: Binding(get: { configManager.ruleConfig?.scoring.kwang.sagwang ?? 0 }, set: { configManager.ruleConfig?.scoring.kwang.sagwang = $0 }))
            settingStepper(label: "오광 점수", value: Binding(get: { configManager.ruleConfig?.scoring.kwang.ogwang ?? 0 }, set: { configManager.ruleConfig?.scoring.kwang.ogwang = $0 }))
            
            Divider().background(Color.white.opacity(0.1))
            
            settingStepper(label: "피 최소 개수", value: Binding(get: { configManager.ruleConfig?.scoring.pi.min_count ?? 10 }, set: { configManager.ruleConfig?.scoring.pi.min_count = $0 }))
            settingStepper(label: "피 1점당 추가 개수", value: Binding(get: { configManager.ruleConfig?.scoring.pi.additional_score ?? 1 }, set: { configManager.ruleConfig?.scoring.pi.additional_score = $0 }))
        }
    }
    
    @ViewBuilder
    private func penaltySettings(config: RuleConfig) -> some View {
        VStack(spacing: 12) {
            settingToggle(label: "자박 (Jabak) 활성화", isOn: Binding(get: { configManager.ruleConfig?.penalties.jabak.enabled ?? false }, set: { configManager.ruleConfig?.penalties.jabak.enabled = $0 }))
            settingStepper(label: "자박 최소 점수", value: Binding(get: { configManager.ruleConfig?.penalties.jabak.min_score_threshold ?? 7 }, set: { configManager.ruleConfig?.penalties.jabak.min_score_threshold = $0 }))
            
            Divider().background(Color.white.opacity(0.1))
            
            settingToggle(label: "피박 활성화", isOn: Binding(get: { configManager.ruleConfig?.penalties.pibak.enabled ?? false }, set: { configManager.ruleConfig?.penalties.pibak.enabled = $0 }))
            settingStepper(label: "피박 기준 개수", value: Binding(get: { configManager.ruleConfig?.penalties.pibak.opponent_min_pi_safe ?? 8 }, set: { configManager.ruleConfig?.penalties.pibak.opponent_min_pi_safe = $0 }))
            
            settingToggle(label: "광박 활성화", isOn: Binding(get: { configManager.ruleConfig?.penalties.gwangbak.enabled ?? false }, set: { configManager.ruleConfig?.penalties.gwangbak.enabled = $0 }))
        }
    }
    
    @ViewBuilder
    private func specialMoveSettings(config: RuleConfig) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("배수 방식")
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(config.special_moves.shake.score_multiplier_type == "multiplicative" ? "지수 (2, 4, 8...)" : "가산 (2, 3, 4...)")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            
            settingToggle(label: "흔들기 활성화", isOn: Binding(get: { configManager.ruleConfig?.special_moves.shake.enabled ?? false }, set: { configManager.ruleConfig?.special_moves.shake.enabled = $0 }))
            settingToggle(label: "폭탄 활성화", isOn: Binding(get: { configManager.ruleConfig?.special_moves.bomb.enabled ?? false }, set: { configManager.ruleConfig?.special_moves.bomb.enabled = $0 }))
            settingToggle(label: "쓸기 활성화", isOn: Binding(get: { configManager.ruleConfig?.special_moves.sweep.enabled ?? false }, set: { configManager.ruleConfig?.special_moves.sweep.enabled = $0 }))
        }
    }
    
    @ViewBuilder
    private func endgameSettings(config: RuleConfig) -> some View {
        VStack(spacing: 12) {
            settingStepper(label: "2인 최소 승리 점수", value: Binding(get: { configManager.ruleConfig?.go_stop.min_score_2_players ?? 7 }, set: { configManager.ruleConfig?.go_stop.min_score_2_players = $0 }))
            settingStepper(label: "3인 최소 승리 점수", value: Binding(get: { configManager.ruleConfig?.go_stop.min_score_3_players ?? 3 }, set: { configManager.ruleConfig?.go_stop.min_score_3_players = $0 }))
            settingStepper(label: "최대 고 횟수", value: Binding(get: { configManager.ruleConfig?.endgame.max_go_count ?? 5 }, set: { configManager.ruleConfig?.endgame.max_go_count = $0 }))
            settingStepper(label: "라운드 최대 점수", value: Binding(get: { configManager.ruleConfig?.endgame.max_round_score ?? 50 }, set: { configManager.ruleConfig?.endgame.max_round_score = $0 }))
        }
    }
    
    private func settingStepper(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Stepper("\(value.wrappedValue)", value: value)
                .foregroundColor(.white)
                .labelsHidden()
            Text("\(value.wrappedValue)")
                .foregroundColor(.white)
                .frame(width: 30)
                .font(.system(.body, design: .monospaced))
        }
    }
    
    private func settingToggle(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .foregroundColor(.white.opacity(0.8))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
    }
}
